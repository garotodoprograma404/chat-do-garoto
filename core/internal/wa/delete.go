package wa

import (
	"context"
	"errors"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/appstate"
	"go.mau.fi/whatsmeow/proto/waCommon"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waSyncAction"
	"go.mau.fi/whatsmeow/types"
	waevents "go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

// Deletions.
const (
	// EventDeleted tells the app what was deleted. data: {"chat", "scope",
	// "id" (message scopes), "message" (revoked: the message as it is now)}.
	EventDeleted = "wa_deleted"
	// EventDeleteFailed reports a "delete for everyone" WhatsApp refused.
	// data: {"chat", "id"}.
	EventDeleteFailed = "wa_delete_failed"

	ScopeChat    = "chat"    // the whole chat is gone
	ScopeClear   = "clear"   // the messages are gone, the chat stays
	ScopeMessage = "message" // one message is gone
	ScopeRevoked = "revoked" // one message lost its content

	// EventRevokeDone ends "delete the chat and my messages for everyone"
	// data: {"chat", "revoked", "failed"}.
	EventRevokeDone = "wa_revoke_done"

	// CodeOffline is the error for an action that needs the connection.
	CodeOffline = "offline"
)

// MaxRevokeOnDelete bounds how many of my messages a chat deletion deletes
// for everyone, and revokeGap spaces them, so it never looks like a bulk
// action to WhatsApp.
const MaxRevokeOnDelete = 50

var revokeGap = 500 * time.Millisecond

// RevokeWindow is how long after sending WhatsApp lets a message be deleted
// for everyone (2 days and 12 hours, checked on 2026-10-02).
const RevokeWindow = 60 * time.Hour

// syncTimeout bounds one deletion sent to WhatsApp.
const syncTimeout = time.Minute

// DeleteChat deletes a chat here, with its media, and in my WhatsApp
// Without connection the WhatsApp part waits in the queue.
// forEveryone also deletes for everyone my messages still inside the
// window (up to MaxRevokeOnDelete): it needs the connection, and ends
// as wa_revoke_done.
func (s *Session) DeleteChat(chat string, forEveryone bool) error {
	client, msgs, media, err := s.deleting(chat)
	if err != nil {
		return err
	}
	ctx := context.Background()
	var revoke []string
	if forEveryone {
		if !s.delivererOf(client).IsConnected() {
			return &bridge.Error{Code: CodeOffline, Message: "not connected"}
		}
		now := time.Now()
		mine, err := msgs.Mine(ctx, chat, now.Add(-RevokeWindow).UnixMilli(), MaxRevokeOnDelete)
		if err != nil {
			return err
		}
		for _, m := range mine {
			if CanRevoke(m, now) {
				revoke = append(revoke, m.ID)
			}
		}
	}
	// Queued before deleting: if the app stops in between, WhatsApp still
	// gets it on the next connection.
	// An empty chat (cleared) still goes: WhatsApp keeps it in the list.
	pending := msgstore.Pending{Kind: msgstore.PendingDeleteChat, Chat: chat}
	if last, err := msgs.Newest(ctx, chat); err == nil {
		pending.ID, pending.FromMe, pending.Sender, pending.TS = last.ID, last.FromMe, last.SenderJID, last.Timestamp
	} else if !errors.Is(err, msgstore.ErrNotFound) {
		return err
	}
	if err := msgs.AddPending(ctx, pending); err != nil {
		return err
	}
	ids, err := msgs.DeleteChat(ctx, chat, 0)
	dropMedia(media, chat, ids...)
	if err != nil {
		return err
	}
	s.hub.Emit(EventDeleted, map[string]any{"chat": chat, "scope": ScopeChat})
	if !forEveryone {
		s.startSync(client)
		return nil
	}
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		s.revokeAll(client, chat, revoke)
		s.flushPending(client)
	}()
	return nil
}

// revokeAll deletes messages ids of chat for everyone, one at a time, and
// tells the app how many went.
func (s *Session) revokeAll(client *whatsmeow.Client, chat string, ids []string) {
	d := s.delivererOf(client)
	to, _ := types.ParseJID(chat)
	done, failed := 0, 0
	for i, id := range ids {
		if i > 0 {
			time.Sleep(revokeGap)
		}
		ctx, cancel := context.WithTimeout(context.Background(), sendTimeout)
		_, err := d.SendMessage(ctx, to, revokeOf(chat, id))
		cancel()
		if err != nil {
			failed++
			continue
		}
		done++
	}
	s.hub.Emit(EventRevokeDone, map[string]any{"chat": chat, "revoked": done, "failed": failed})
}

// revokeOf is the message that deletes my message id for everyone.
func revokeOf(chat, id string) *waE2E.Message {
	return &waE2E.Message{ProtocolMessage: &waE2E.ProtocolMessage{
		Type: waE2E.ProtocolMessage_REVOKE.Enum(),
		Key:  &waCommon.MessageKey{FromMe: proto.Bool(true), ID: proto.String(id), RemoteJID: proto.String(chat)},
	}}
}

// DeleteForMe deletes one message here and in my WhatsApp ("apagar para
// mim").
func (s *Session) DeleteForMe(chat, id string) error {
	client, msgs, media, err := s.deleting(chat)
	if err != nil {
		return err
	}
	ctx := context.Background()
	m, err := msgs.Message(ctx, chat, id)
	if errors.Is(err, msgstore.ErrNotFound) {
		return invalidArgument("message not found")
	}
	if err != nil {
		return err
	}
	if err := msgs.AddPending(ctx, msgstore.Pending{
		Kind: msgstore.PendingDeleteForMe, Chat: chat, ID: id,
		FromMe: m.FromMe, Sender: m.SenderJID, TS: m.Timestamp,
	}); err != nil {
		return err
	}
	had, err := msgs.DeleteMessage(ctx, chat, id)
	if had {
		dropMedia(media, chat, id)
	}
	if err != nil {
		return err
	}
	s.hub.Emit(EventDeleted, map[string]any{"chat": chat, "id": id, "scope": ScopeMessage})
	s.startSync(client)
	return nil
}

// CanRevoke reports whether m may be deleted for everyone at now: mine,
// sent (not failed nor still sending), not revoked and recent enough.
func CanRevoke(m msgstore.Message, now time.Time) bool {
	if !m.FromMe || m.Kind == msgstore.KindRevoked {
		return false
	}
	if m.Status == msgstore.StatusSending || m.Status == msgstore.StatusFailed {
		return false
	}
	return now.Sub(time.UnixMilli(m.Timestamp)) < RevokeWindow
}

// RevokeForEveryone deletes a message of mine for everyone. It needs
// the connection; the revocation runs in the background and ends as
// wa_deleted (scope "revoked") or wa_delete_failed.
func (s *Session) RevokeForEveryone(chat, id string) error {
	client, msgs, media, err := s.deleting(chat)
	if err != nil {
		return err
	}
	to, _ := types.ParseJID(chat)
	m, err := msgs.Message(context.Background(), chat, id)
	if errors.Is(err, msgstore.ErrNotFound) {
		return invalidArgument("message not found")
	}
	if err != nil {
		return err
	}
	if !CanRevoke(m, time.Now()) {
		return invalidArgument("message cannot be deleted for everyone")
	}
	d := s.delivererOf(client)
	if !d.IsConnected() {
		return &bridge.Error{Code: CodeOffline, Message: "not connected"}
	}
	revoke := revokeOf(chat, id)
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		ctx, cancel := context.WithTimeout(context.Background(), sendTimeout)
		_, err := d.SendMessage(ctx, to, revoke)
		cancel()
		if err != nil {
			s.hub.Emit(EventDeleteFailed, map[string]any{"chat": chat, "id": id})
			return
		}
		s.applyRevoke(msgs, media, chat, id)
	}()
	return nil
}

// deleting checks the chat and returns what a deletion needs.
func (s *Session) deleting(chat string) (*whatsmeow.Client, *msgstore.Store, *vault.Vault, error) {
	jid, err := types.ParseJID(chat)
	switch {
	case err != nil || jid.User == "":
		return nil, nil, nil, invalidArgument("invalid chat")
	case jid.Server != types.DefaultUserServer && jid.Server != types.HiddenUserServer && jid.Server != types.GroupServer:
		return nil, nil, nil, invalidArgument("invalid chat")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.msgs == nil {
		return nil, nil, nil, invalidState("call cc_wa_start first")
	}
	return s.client, s.msgs, s.media, nil
}

// dropMedia deletes from the vault the media of messages ids of chat.
func dropMedia(media *vault.Vault, chat string, ids ...string) {
	if media == nil {
		return
	}
	for _, id := range ids {
		_ = media.Delete(vault.Name(chat, id, PartFull))
		_ = media.Delete(vault.Name(chat, id, PartThumb))
	}
}

// startSync sends the queued deletions in the background.
func (s *Session) startSync(client *whatsmeow.Client) {
	if client == nil {
		return
	}
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		s.flushPending(client)
	}()
}

// flushPending sends the queued deletions to WhatsApp, oldest first. One
// that fails stays queued for the next connection without holding back the
// others.
func (s *Session) flushPending(client *whatsmeow.Client) {
	s.syncMu.Lock()
	defer s.syncMu.Unlock()
	msgs := s.storeOf(client)
	if msgs == nil {
		return
	}
	d := s.delivererOf(client)
	if !d.IsConnected() {
		return
	}
	ctx := context.Background()
	list, err := msgs.PendingList(ctx)
	if err != nil {
		return
	}
	log := s.logger("sync")
	for _, p := range list {
		patch, ok := patchOf(p, time.Now())
		if !ok {
			_ = msgs.DonePending(ctx, p.Seq) // nothing WhatsApp could take
			continue
		}
		sctx, cancel := context.WithTimeout(ctx, syncTimeout)
		err := d.SendAppState(sctx, patch)
		cancel()
		if err != nil {
			log.Warnf("%s not sent: %v", p.Kind, err) // diagnostics only, digits masked
			continue
		}
		log.Infof("%s sent", p.Kind)
		_ = msgs.DonePending(ctx, p.Seq)
	}
}

// patchOf builds the app state change of a queued deletion at now. A chat
// is deleted up to now, not up to its last message: the time stored for a
// message sent from here is the phone's, a moment before WhatsApp's, and
// the phone would keep that "newer" message and the chat.
func patchOf(p msgstore.Pending, now time.Time) (appstate.PatchInfo, bool) {
	chat, err := types.ParseJID(p.Chat)
	if err != nil {
		return appstate.PatchInfo{}, false
	}
	participant := "0"
	if !p.FromMe && chat.Server == types.GroupServer && p.Sender != "" {
		participant = p.Sender
	}
	switch p.Kind {
	case msgstore.PendingDeleteChat:
		patch := appstate.BuildDeleteChat(chat, now, nil, true)
		if p.ID != "" {
			key := &waCommon.MessageKey{FromMe: proto.Bool(p.FromMe), ID: proto.String(p.ID), RemoteJID: proto.String(p.Chat)}
			if participant != "0" {
				key.Participant = proto.String(participant)
			}
			r := patch.Mutations[0].Value.GetDeleteChatAction().GetMessageRange()
			r.Messages = []*waSyncAction.SyncActionMessage{{Key: key, Timestamp: proto.Int64(p.TS / 1000)}}
		}
		return patch, true
	case msgstore.PendingDeleteForMe:
		fromMe := "0"
		if p.FromMe {
			fromMe = "1"
		}
		return appstate.PatchInfo{
			Type: appstate.WAPatchRegularHigh,
			Mutations: []appstate.MutationInfo{{
				Index:   []string{appstate.IndexDeleteMessageForMe, p.Chat, p.ID, fromMe, participant},
				Version: 3,
				Value: &waSyncAction.SyncActionValue{
					DeleteMessageForMeAction: &waSyncAction.DeleteMessageForMeAction{
						DeleteMedia:      proto.Bool(true),
						MessageTimestamp: proto.Int64(p.TS / 1000),
					},
				},
			}},
		}, true
	}
	return appstate.PatchInfo{}, false
}

// applyRevoke erases a message deleted for everyone and tells the app.
func (s *Session) applyRevoke(msgs *msgstore.Store, media *vault.Vault, chat, id string) {
	m, had, err := msgs.Revoke(context.Background(), chat, id)
	if err != nil {
		return
	}
	if had {
		dropMedia(media, chat, id)
	}
	s.hub.Emit(EventDeleted, map[string]any{"chat": chat, "id": id, "scope": ScopeRevoked, "message": m})
}

// candidates lists the chats a WhatsApp update may mean: the JID itself and
// the contact's other address (phone number or LID), when known.
func candidates(client *whatsmeow.Client, jid types.JID) []string {
	jid = jid.ToNonAD()
	out := []string{jid.String()}
	if client == nil || client.Store.LIDs == nil {
		return out
	}
	ctx := context.Background()
	switch jid.Server {
	case types.HiddenUserServer:
		if pn, err := client.Store.LIDs.GetPNForLID(ctx, jid); err == nil && !pn.IsEmpty() {
			out = append(out, pn.ToNonAD().String())
		}
	case types.DefaultUserServer:
		if lid, err := client.Store.LIDs.GetLIDForPN(ctx, jid); err == nil && !lid.IsEmpty() {
			out = append(out, lid.ToNonAD().String())
		}
	}
	return out
}

// upToOf turns the end of a WhatsApp message range (seconds) into the last
// millisecond it covers; 0 means everything.
func upToOf(r *waSyncAction.SyncActionMessageRange) int64 {
	sec := r.GetLastMessageTimestamp()
	if sec <= 0 {
		return 0
	}
	return (sec+1)*1000 - 1
}

// onChatDeleted applies a chat deleted or cleared on the phone.
func (s *Session) onChatDeleted(client *whatsmeow.Client, jid types.JID, r *waSyncAction.SyncActionMessageRange, clear bool) {
	msgs, media := s.storesOf(client)
	if msgs == nil {
		return
	}
	ctx := context.Background()
	scope := ScopeChat
	if clear {
		scope = ScopeClear
	}
	for _, chat := range candidates(client, jid) {
		if ok, _ := msgs.HasChat(ctx, chat); !ok {
			continue
		}
		var ids []string
		var err error
		if clear {
			ids, err = msgs.ClearChat(ctx, chat, upToOf(r))
		} else {
			ids, err = msgs.DeleteChat(ctx, chat, upToOf(r))
		}
		dropMedia(media, chat, ids...)
		if err == nil {
			s.hub.Emit(EventDeleted, map[string]any{"chat": chat, "scope": scope})
		}
	}
}

// onDeleteForMe applies a message deleted for me on the phone.
func (s *Session) onDeleteForMe(client *whatsmeow.Client, e *waevents.DeleteForMe) {
	msgs, media := s.storesOf(client)
	if msgs == nil {
		return
	}
	ctx := context.Background()
	chat, err := msgs.ChatOf(ctx, e.MessageID, candidates(client, e.ChatJID)...)
	if err != nil || chat == "" {
		return
	}
	had, err := msgs.DeleteMessage(ctx, chat, e.MessageID)
	if had {
		dropMedia(media, chat, e.MessageID)
	}
	if err == nil {
		s.hub.Emit(EventDeleted, map[string]any{"chat": chat, "id": e.MessageID, "scope": ScopeMessage})
	}
}

// onRevoke applies a message deleted for everyone by whoever sent it, from
// a contact or from my other devices. Only the sender (or, in groups,
// an admin) can revoke; anything else is ignored.
func (s *Session) onRevoke(client *whatsmeow.Client, evt *waevents.Message, key *waCommon.MessageKey) {
	msgs, media := s.storesOf(client)
	if msgs == nil || key.GetID() == "" {
		return
	}
	ctx := context.Background()
	chats := candidates(client, evt.Info.Chat)
	if remote, err := types.ParseJID(key.GetRemoteJID()); err == nil && !remote.IsEmpty() {
		chats = append(chats, candidates(client, remote)...)
	}
	chat, err := msgs.ChatOf(ctx, key.GetID(), chats...)
	if err != nil || chat == "" {
		return
	}
	m, err := msgs.Message(ctx, chat, key.GetID())
	if err != nil || m.Kind == msgstore.KindRevoked {
		return
	}
	if m.FromMe != evt.Info.IsFromMe && evt.Info.Chat.Server != types.GroupServer {
		return
	}
	s.applyRevoke(msgs, media, chat, key.GetID())
}
