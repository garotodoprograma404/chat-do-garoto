package wa

import (
	"context"
	"errors"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	waevents "go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/msgstore"
)

// EventMessageStatus reports a new delivery status of one of my messages
// data: {"chat", "id", "status"}.
const EventMessageStatus = "wa_message_status"

// maxTextBytes is the longest text WhatsApp accepts in one message.
const maxTextBytes = 65536

// sendTimeout bounds one send, including encryption and the server reply.
const sendTimeout = 90 * time.Second

func invalidArgument(message string) error {
	return &bridge.Error{Code: bridge.CodeInvalidArgument, Message: message}
}

// SendText stores a text message to chat as "sending" and returns it at
// once; the send runs in the background and ends as wa_message_status. It
// never retries on its own.
func (s *Session) SendText(chat, text string) (msgstore.Message, error) {
	if strings.TrimSpace(text) == "" {
		return msgstore.Message{}, invalidArgument("text is empty")
	}
	if len(text) > maxTextBytes {
		return msgstore.Message{}, invalidArgument("text is too long")
	}
	to, err := types.ParseJID(chat)
	if err != nil || to.User == "" || to.Server == types.BroadcastServer {
		return msgstore.Message{}, invalidArgument("invalid chat")
	}
	to = to.ToNonAD()

	s.mu.Lock()
	client, msgs := s.client, s.msgs
	s.mu.Unlock()
	if msgs == nil {
		return msgstore.Message{}, invalidState("call cc_wa_start first")
	}
	own := client.Store.ID
	if own == nil {
		return msgstore.Message{}, invalidState("not paired")
	}

	m := msgstore.Message{
		ChatJID:   to.String(),
		ID:        client.GenerateMessageID(),
		FromMe:    true,
		SenderJID: own.ToNonAD().String(),
		Kind:      msgstore.KindText,
		Text:      text,
		Timestamp: time.Now().UnixMilli(),
		Status:    msgstore.StatusSending,
	}
	if _, err := msgs.Save(context.Background(), []msgstore.Message{m}); err != nil {
		return msgstore.Message{}, err
	}
	s.hub.Emit(EventMessage, m) // moves the chat to the top of the list
	s.startDelivery(client, msgs, to, m)
	return m, nil
}

// Retry sends a failed message again with the same ID, so the contact never
// gets two copies.
func (s *Session) Retry(chat, id string) (msgstore.Message, error) {
	s.mu.Lock()
	client, msgs := s.client, s.msgs
	s.mu.Unlock()
	if msgs == nil {
		return msgstore.Message{}, invalidState("call cc_wa_start first")
	}
	ctx := context.Background()
	m, err := msgs.Message(ctx, chat, id)
	if errors.Is(err, msgstore.ErrNotFound) {
		return msgstore.Message{}, invalidArgument("message not found")
	}
	if err != nil {
		return msgstore.Message{}, err
	}
	to, err := types.ParseJID(m.ChatJID)
	if err != nil || !m.FromMe || (m.Kind != msgstore.KindText && !resendable(ctx, msgs, m)) {
		return msgstore.Message{}, invalidArgument("message cannot be resent")
	}
	if m.Status != msgstore.StatusFailed {
		return msgstore.Message{}, invalidState("message has not failed")
	}
	s.setStatus(msgs, m.ID, msgstore.StatusSending)
	m.Status = msgstore.StatusSending
	if m.Kind == msgstore.KindText {
		s.startDelivery(client, msgs, to, m)
	} else {
		// A media of mine is resent from the vault.
		s.mu.Lock()
		media := s.media
		s.mu.Unlock()
		s.startMediaDelivery(client, msgs, media, to, m)
	}
	return m, nil
}

// resendable reports whether a media of mine can be sent again: it is in
// the vault, or its upload (or the forwarded media) is stored.
func resendable(ctx context.Context, msgs *msgstore.Store, m msgstore.Message) bool {
	if m.Media == msgstore.MediaDownloaded {
		return true
	}
	rec, err := msgs.Media(ctx, m.ChatJID, m.ID)
	return err == nil && len(rec.Proto) > 0
}

// startDelivery sends m in the background. The session lock is not held:
// SendMessage waits on the network (core/DESENVOLVIMENTO.md). A forwarded text goes
// with the mark.
func (s *Session) startDelivery(client *whatsmeow.Client, msgs *msgstore.Store, to types.JID, m msgstore.Message) {
	d := s.delivererOf(client)
	msg := &waE2E.Message{Conversation: proto.String(m.Text)}
	if m.Forwarded {
		msg = &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{
			Text:        proto.String(m.Text),
			ContextInfo: &waE2E.ContextInfo{IsForwarded: proto.Bool(true), ForwardingScore: proto.Uint32(1)},
		}}
	}
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		status := msgstore.StatusFailed
		if d.IsConnected() {
			ctx, cancel := context.WithTimeout(context.Background(), sendTimeout)
			_, err := d.SendMessage(ctx, to, msg, whatsmeow.SendRequestExtra{ID: m.ID})
			cancel()
			if err == nil {
				status = msgstore.StatusSent
			}
		}
		s.setStatus(msgs, m.ID, status)
	}()
}

// setStatus records a status change and tells the app when it happened.
func (s *Session) setStatus(msgs *msgstore.Store, id, status string) {
	chats, err := msgs.SetStatus(context.Background(), id, status)
	if err != nil {
		s.hub.Emit(EventError, map[string]any{"code": ErrStoreFailed})
		return
	}
	for _, chat := range chats {
		s.hub.Emit(EventMessageStatus, map[string]any{"chat": chat, "id": id, "status": status})
	}
}

// onReceipt applies delivery and read receipts from contacts to my
// messages, including those sent from the phone.
func (s *Session) onReceipt(client *whatsmeow.Client, evt *waevents.Receipt) {
	status, ok := receiptStatus(evt)
	if !ok {
		return
	}
	msgs := s.storeOf(client)
	if msgs == nil {
		return
	}
	for _, id := range evt.MessageIDs {
		s.setStatus(msgs, id, status)
	}
}

// receiptStatus maps a receipt to a status. Receipts from my own devices
// (read-self and the like) say nothing about the contact.
func receiptStatus(evt *waevents.Receipt) (string, bool) {
	if evt == nil || evt.IsFromMe {
		return "", false
	}
	switch evt.Type {
	case types.ReceiptTypeDelivered:
		return msgstore.StatusDelivered, true
	case types.ReceiptTypeRead, types.ReceiptTypePlayed:
		return msgstore.StatusRead, true
	}
	return "", false
}
