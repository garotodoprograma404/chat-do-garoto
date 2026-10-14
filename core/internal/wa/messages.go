package wa

import (
	"context"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	waevents "go.mau.fi/whatsmeow/types/events"

	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

// Event types for messages.
const (
	EventMessage = "wa_message" // data: the stored message
	EventHistory = "wa_history" // data: {"chats": n, "messages": n}
)

// ErrStoreFailed is sent in wa_error when a message could not be stored.
const ErrStoreFailed = "store_failed"

// storeOf returns the message store if client is still the current one.
func (s *Session) storeOf(client *whatsmeow.Client) *msgstore.Store {
	msgs, _ := s.storesOf(client)
	return msgs
}

// storesOf returns the message store and the media vault if client is still
// the current one.
func (s *Session) storesOf(client *whatsmeow.Client) (*msgstore.Store, *vault.Vault) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.client != client {
		return nil, nil
	}
	return s.msgs, s.media
}

// onMessage stores a live message and tells the app. Nothing is sent back
// to WhatsApp: no read receipt, no presence.
func (s *Session) onMessage(client *whatsmeow.Client, evt *waevents.Message) {
	msgs, media := s.storesOf(client)
	if msgs == nil {
		return
	}
	// REVOKE is the type's zero value: only a protocol message that sets it
	// counts.
	if pm := evt.Message.GetProtocolMessage(); pm != nil && pm.Type != nil && pm.GetType() == waE2E.ProtocolMessage_REVOKE {
		s.onRevoke(client, evt, pm.GetKey())
		return
	}
	m, ok := extract(evt)
	if !ok {
		return
	}
	ctx := context.Background()
	added, err := msgs.Save(ctx, []msgstore.Message{m})
	if err != nil {
		s.hub.Emit(EventError, map[string]any{"code": ErrStoreFailed})
		return
	}
	if len(added) == 0 {
		return
	}
	storeMedia(ctx, msgs, media, &m, evt.Message)
	fallback := ""
	if !evt.Info.IsFromMe {
		fallback = evt.Info.PushName
	}
	s.ensureChatName(ctx, client, msgs, evt.Info.Chat, fallback)
	s.hub.Emit(EventMessage, m)
}

// onHistory stores the history WhatsApp sends after pairing.
func (s *Session) onHistory(client *whatsmeow.Client, evt *waevents.HistorySync) {
	msgs, media := s.storesOf(client)
	if msgs == nil || evt.Data == nil {
		return
	}
	ctx := context.Background()
	chats, total := 0, 0
	for _, conv := range evt.Data.GetConversations() {
		chat, err := types.ParseJID(conv.GetID())
		if err != nil || chat.Server == types.BroadcastServer {
			continue
		}
		var batch []msgstore.Message
		withMedia := map[int]*waE2E.Message{}
		for _, hm := range conv.GetMessages() {
			parsed, err := client.ParseWebMessage(chat, hm.GetMessage())
			if err != nil {
				continue
			}
			if m, ok := extract(parsed); ok {
				if _, _, has := mediaOf(parsed.Message); has {
					withMedia[len(batch)] = parsed.Message
				}
				batch = append(batch, m)
			}
		}
		if len(batch) == 0 {
			continue
		}
		added, err := msgs.Save(ctx, batch)
		if err != nil {
			s.hub.Emit(EventError, map[string]any{"code": ErrStoreFailed})
			return
		}
		for i, msg := range withMedia {
			storeMedia(ctx, msgs, media, &batch[i], msg)
		}
		name := conv.GetName()
		if name == "" {
			name = conv.GetDisplayName()
		}
		if name != "" {
			_ = msgs.SetChatName(ctx, chat.ToNonAD().String(), name)
		} else {
			s.ensureChatName(ctx, client, msgs, chat, "")
		}
		chats++
		total += len(added)
	}
	s.hub.Emit(EventHistory, map[string]any{"chats": chats, "messages": total})
	s.fillMissingNames(client)
}

// ensureChatName fills the chat name from the address book when missing:
// saved name, then profile name, then fallback. Groups get their name from
// the history (no network call here).
func (s *Session) ensureChatName(ctx context.Context, client *whatsmeow.Client, msgs *msgstore.Store, chat types.JID, fallback string) {
	jid := chat.ToNonAD().String()
	if name, _ := msgs.ChatName(ctx, jid); name != "" || chat.Server == types.GroupServer {
		return
	}
	name := fallback
	lookup := chat.ToNonAD()
	// Chats under a private ID (LID) are named after the phone number behind
	// it, when WhatsApp told us which one it is.
	if chat.Server == types.HiddenUserServer && client.Store.LIDs != nil {
		if pn, err := client.Store.LIDs.GetPNForLID(ctx, lookup); err == nil && !pn.IsEmpty() {
			lookup = pn.ToNonAD()
			if name == "" {
				name = pn.User
			}
		}
	}
	if client.Store.Contacts == nil { // not paired yet: no address book
		_ = msgs.SetChatName(ctx, jid, name)
		return
	}
	if c, err := client.Store.Contacts.GetContact(ctx, lookup); err == nil && c.Found {
		for _, n := range []string{c.FullName, c.FirstName, c.PushName, c.BusinessName} {
			if n != "" {
				name = n
				break
			}
		}
	}
	_ = msgs.SetChatName(ctx, jid, name)
}

// PhoneOf returns the phone number (digits) behind a one-to-one chat: the
// JID itself, or, under a private ID (LID), the number WhatsApp told us
// "" when unknown.
func (s *Session) PhoneOf(chat string) (string, error) {
	jid, err := types.ParseJID(chat)
	if err != nil {
		return "", invalidArgument("invalid chat")
	}
	switch jid.Server {
	case types.DefaultUserServer:
		return jid.User, nil
	case types.HiddenUserServer:
	default:
		return "", nil
	}
	s.mu.Lock()
	client := s.client
	s.mu.Unlock()
	if client == nil {
		return "", invalidState("call cc_wa_start first")
	}
	if client.Store.LIDs == nil {
		return "", nil
	}
	pn, err := client.Store.LIDs.GetPNForLID(context.Background(), jid.ToNonAD())
	if err != nil || pn.IsEmpty() {
		return "", nil
	}
	return pn.User, nil
}

// ChatForPhone returns the stored chat of a phone number (digits): the
// phone's own chat, or the chat under its private ID (LID) when WhatsApp
// told which one it is. "" when there is none.
func (s *Session) ChatForPhone(phone string) (string, error) {
	for _, c := range phone {
		if c < '0' || c > '9' {
			return "", invalidArgument("phone must be digits")
		}
	}
	if phone == "" {
		return "", invalidArgument("phone is empty")
	}
	s.mu.Lock()
	client, msgs := s.client, s.msgs
	s.mu.Unlock()
	if msgs == nil {
		return "", invalidState("call cc_wa_start first")
	}
	ctx := context.Background()
	pn := types.NewJID(phone, types.DefaultUserServer)
	if ok, err := msgs.HasChat(ctx, pn.String()); err != nil || ok {
		if ok {
			return pn.String(), nil
		}
		return "", err
	}
	if client.Store.LIDs == nil {
		return "", nil
	}
	lid, err := client.Store.LIDs.GetLIDForPN(ctx, pn)
	if err != nil || lid.IsEmpty() {
		return "", nil
	}
	if ok, _ := msgs.HasChat(ctx, lid.String()); ok {
		return lid.String(), nil
	}
	return "", nil
}

// SearchMessages returns stored messages whose text matches typed,
// ignoring accents and case, newest first.
func (s *Session) SearchMessages(typed string, limit int) ([]msgstore.Message, error) {
	s.mu.Lock()
	msgs := s.msgs
	s.mu.Unlock()
	if msgs == nil {
		return nil, invalidState("call cc_wa_start first")
	}
	return msgs.Search(context.Background(), typed, limit)
}

// ListChats returns the stored chats, newest first.
func (s *Session) ListChats(limit int) ([]msgstore.Chat, error) {
	s.mu.Lock()
	msgs := s.msgs
	s.mu.Unlock()
	if msgs == nil {
		return nil, invalidState("call cc_wa_start first")
	}
	return msgs.ListChats(context.Background(), limit)
}

// ListMessages returns a page of a chat's messages, oldest first.
func (s *Session) ListMessages(chat string, beforeTS int64, limit int) ([]msgstore.Message, error) {
	s.mu.Lock()
	msgs := s.msgs
	s.mu.Unlock()
	if msgs == nil {
		return nil, invalidState("call cc_wa_start first")
	}
	return msgs.ListMessages(context.Background(), chat, beforeTS, limit)
}

// fillMissingNames names chats stored without a name, once the address book
// and the LID map are available (after connecting and after history).
func (s *Session) fillMissingNames(client *whatsmeow.Client) {
	msgs := s.storeOf(client)
	if msgs == nil {
		return
	}
	ctx := context.Background()
	jids, err := msgs.ChatsWithoutName(ctx)
	if err != nil {
		return
	}
	for _, j := range jids {
		if chat, err := types.ParseJID(j); err == nil {
			s.ensureChatName(ctx, client, msgs, chat, "")
		}
	}
	if len(jids) > 0 {
		s.hub.Emit(EventHistory, map[string]any{"chats": 0, "messages": 0})
	}
}
