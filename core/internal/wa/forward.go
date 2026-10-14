package wa

import (
	"context"
	"errors"
	"time"

	"go.mau.fi/whatsmeow/types"

	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

// Forward sends a copy of a message to another chat, with the "forwarded"
// mark. A media in the vault is uploaded again (WhatsApp
// may no longer keep old ones); otherwise its stored download data is sent
// as it is, without downloading it first. Returns the copy as "sending".
func (s *Session) Forward(chat, id, toChat string) (msgstore.Message, error) {
	to, err := types.ParseJID(toChat)
	if err != nil || to.User == "" || to.Server == types.BroadcastServer {
		return msgstore.Message{}, invalidArgument("invalid chat")
	}
	to = to.ToNonAD()

	s.mu.Lock()
	client, msgs, media := s.client, s.msgs, s.media
	s.mu.Unlock()
	if msgs == nil {
		return msgstore.Message{}, invalidState("call cc_wa_start first")
	}
	own := client.Store.ID
	if own == nil {
		return msgstore.Message{}, invalidState("not paired")
	}
	ctx := context.Background()
	src, err := msgs.Message(ctx, chat, id)
	if errors.Is(err, msgstore.ErrNotFound) {
		return msgstore.Message{}, invalidArgument("message not found")
	}
	if err != nil {
		return msgstore.Message{}, err
	}
	m := msgstore.Message{
		ChatJID:   to.String(),
		ID:        client.GenerateMessageID(),
		FromMe:    true,
		SenderJID: own.ToNonAD().String(),
		Kind:      src.Kind,
		Text:      src.Text,
		Timestamp: time.Now().UnixMilli(),
		Status:    msgstore.StatusSending,
		Forwarded: true,
	}
	if src.Kind == msgstore.KindText {
		if _, err := msgs.Save(ctx, []msgstore.Message{m}); err != nil {
			return msgstore.Message{}, err
		}
		s.hub.Emit(EventMessage, m)
		s.startDelivery(client, msgs, to, m)
		return m, nil
	}

	rec, err := msgs.Media(ctx, chat, id)
	if errors.Is(err, msgstore.ErrNotFound) {
		return msgstore.Message{}, invalidArgument("message cannot be forwarded")
	}
	if err != nil {
		return msgstore.Message{}, err
	}
	full, fullErr := media.Get(vault.Name(chat, id, PartFull))
	if fullErr != nil && len(rec.Proto) == 0 {
		return msgstore.Message{}, invalidArgument("media not available")
	}
	if _, err := msgs.Save(ctx, []msgstore.Message{m}); err != nil {
		return msgstore.Message{}, err
	}
	copied := rec
	copied.ChatJID, copied.ID = m.ChatJID, m.ID
	copied.State = msgstore.MediaRemote
	if fullErr == nil {
		// In the vault: the copy keeps it and is uploaded again.
		defer clear(full)
		if err := media.Put(vault.Name(m.ChatJID, m.ID, PartFull), full); err != nil {
			return msgstore.Message{}, err
		}
		copied.State, copied.Proto = msgstore.MediaDownloaded, nil
	}
	copied.Thumb = false
	if thumb, err := media.Get(vault.Name(chat, id, PartThumb)); err == nil {
		copied.Thumb = media.Put(vault.Name(m.ChatJID, m.ID, PartThumb), thumb) == nil
		if copied.Thumb && copied.State == msgstore.MediaRemote {
			copied.State = msgstore.MediaThumb
		}
	}
	if err := msgs.SaveMedia(ctx, copied); err != nil {
		return msgstore.Message{}, err
	}
	fillMedia(ctx, msgs, &m)
	s.hub.Emit(EventMessage, m)
	s.startMediaDelivery(client, msgs, media, to, m)
	return m, nil
}
