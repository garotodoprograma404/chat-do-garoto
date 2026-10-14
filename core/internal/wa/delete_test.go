package wa

import (
	"context"
	"errors"
	"testing"
	"time"

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

// withPhoto stores a received photo with its thumbnail and full media in
// the vault, and a text after it.
func withPhoto(t *testing.T, s *Session) {
	t.Helper()
	ctx := context.Background()
	now := time.Now().UnixMilli()
	s.msgs.Save(ctx, []msgstore.Message{
		{ChatJID: alice.String(), ID: "P1", SenderJID: alice.String(), Kind: msgstore.KindImage, Text: "foto", Timestamp: now - 2000},
		{ChatJID: alice.String(), ID: "T1", FromMe: true, Kind: msgstore.KindText, Text: "oi", Timestamp: now - 1000, Status: msgstore.StatusSent},
	})
	s.msgs.SaveMedia(ctx, msgstore.MediaRecord{ChatJID: alice.String(), ID: "P1", Kind: msgstore.KindImage, State: msgstore.MediaDownloaded, Thumb: true})
	s.media.Put(vault.Name(alice.String(), "P1", PartFull), []byte("full"))
	s.media.Put(vault.Name(alice.String(), "P1", PartThumb), []byte("thumb"))
}

func lastEvent(got *[]map[string]any) (string, map[string]any) {
	e := (*got)[len(*got)-1]
	data, _ := e["data"].(map[string]any)
	return e["type"].(string), data
}

func TestDeleteChatHereAndInWhatsApp(t *testing.T) {
	s, f, got := sendingSession(t)
	withPhoto(t, s)
	if err := s.DeleteChat(alice.String(), false); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if chats, _ := s.ListChats(10); len(chats) != 0 {
		t.Fatalf("chats = %+v", chats)
	}
	if s.media.Has(vault.Name(alice.String(), "P1", PartFull)) || s.media.Has(vault.Name(alice.String(), "P1", PartThumb)) {
		t.Fatal("media left in the vault")
	}
	if typ, data := lastEvent(got); typ != EventDeleted || data["scope"] != ScopeChat || data["chat"] != alice.String() {
		t.Fatalf("event = %s %v", typ, data)
	}
	if len(f.patches) != 1 {
		t.Fatalf("patches = %d", len(f.patches))
	}
	m := f.patches[0].Mutations[0]
	if f.patches[0].Type != appstate.WAPatchRegularHigh || m.Index[0] != appstate.IndexDeleteChat ||
		m.Index[1] != alice.String() || m.Index[2] != "1" {
		t.Fatalf("patch = %+v", f.patches[0])
	}
	r := m.Value.GetDeleteChatAction().GetMessageRange()
	last := r.GetMessages()[0]
	if last.GetKey().GetID() != "T1" || !last.GetKey().GetFromMe() {
		t.Fatalf("last message key = %+v", last)
	}
	// Up to the deletion, not to the last message: the phone's clock is a
	// moment behind WhatsApp's for messages sent from here.
	if r.GetLastMessageTimestamp() < time.Now().Unix()-5 || last.GetTimestamp() >= r.GetLastMessageTimestamp() {
		t.Fatalf("range = %+v", r)
	}
	if p, _ := s.msgs.PendingList(context.Background()); len(p) != 0 {
		t.Fatalf("queue = %+v", p)
	}
}

func TestDeleteEmptyChatStillGoesToWhatsApp(t *testing.T) {
	s, f, _ := sendingSession(t)
	withPhoto(t, s)
	s.msgs.ClearChat(context.Background(), alice.String(), 0) // cleared on the phone
	if err := s.DeleteChat(alice.String(), false); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if len(f.patches) != 1 {
		t.Fatalf("patches = %d", len(f.patches))
	}
	r := f.patches[0].Mutations[0].Value.GetDeleteChatAction().GetMessageRange()
	if len(r.GetMessages()) != 0 || r.GetLastMessageTimestamp() == 0 {
		t.Fatalf("range = %+v", r)
	}
	if chats, _ := s.ListChats(10); len(chats) != 0 {
		t.Fatalf("chats = %+v", chats)
	}
}

func TestDeleteForMe(t *testing.T) {
	s, f, got := sendingSession(t)
	withPhoto(t, s)
	if err := s.DeleteForMe(alice.String(), "P1"); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	page, _ := s.ListMessages(alice.String(), 0, 10)
	if len(page) != 1 || page[0].ID != "T1" {
		t.Fatalf("messages = %+v", page)
	}
	if s.media.Has(vault.Name(alice.String(), "P1", PartFull)) {
		t.Fatal("media left in the vault")
	}
	if typ, data := lastEvent(got); typ != EventDeleted || data["scope"] != ScopeMessage || data["id"] != "P1" {
		t.Fatalf("event = %s %v", typ, data)
	}
	m := f.patches[0].Mutations[0]
	want := []string{appstate.IndexDeleteMessageForMe, alice.String(), "P1", "0", "0"}
	for i := range want {
		if m.Index[i] != want[i] {
			t.Fatalf("index = %v", m.Index)
		}
	}
	if !m.Value.GetDeleteMessageForMeAction().GetDeleteMedia() {
		t.Fatal("media not deleted on the phone")
	}
	if err := s.DeleteForMe(alice.String(), "nope"); err == nil {
		t.Fatal("missing message accepted")
	}
}

func TestDeletionsWaitForTheConnection(t *testing.T) {
	s, f, _ := sendingSession(t)
	withPhoto(t, s)
	f.connected = false
	s.DeleteForMe(alice.String(), "T1")
	s.DeleteChat(alice.String(), false)
	s.sends.Wait()
	if len(f.patches) != 0 {
		t.Fatal("sent while offline")
	}
	if page, _ := s.ListMessages(alice.String(), 0, 10); len(page) != 0 {
		t.Fatal("not deleted here at once")
	}
	if p, _ := s.msgs.PendingList(context.Background()); len(p) != 2 {
		t.Fatalf("queue = %+v", p)
	}
	// WhatsApp refuses one: it stays, the other goes.
	f.connected = true
	f.syncErr = errors.New("busy")
	s.flushPending(s.client)
	if p, _ := s.msgs.PendingList(context.Background()); len(p) != 2 {
		t.Fatalf("queue after a failure = %+v", p)
	}
	f.syncErr = nil
	s.handle(s.client, &waevents.Connected{}) // what reconnecting does
	s.sends.Wait()
	if len(f.patches) != 2 || f.patches[0].Mutations[0].Index[0] != appstate.IndexDeleteMessageForMe {
		t.Fatalf("patches = %+v", f.patches)
	}
	if p, _ := s.msgs.PendingList(context.Background()); len(p) != 0 {
		t.Fatalf("queue = %+v", p)
	}
}

func TestGroupMessagesNameTheSender(t *testing.T) {
	p, ok := patchOf(msgstore.Pending{Kind: msgstore.PendingDeleteForMe, Chat: group.String(), ID: "G1", Sender: alice.String(), TS: 5000}, time.Now())
	if !ok || p.Mutations[0].Index[4] != alice.String() ||
		p.Mutations[0].Value.GetDeleteMessageForMeAction().GetMessageTimestamp() != 5 {
		t.Fatalf("patch = %+v", p)
	}
	p, _ = patchOf(msgstore.Pending{Kind: msgstore.PendingDeleteChat, Chat: group.String(), ID: "G1", Sender: alice.String(), TS: 5000}, time.Now())
	key := p.Mutations[0].Value.GetDeleteChatAction().GetMessageRange().GetMessages()[0].GetKey()
	if key.GetParticipant() != alice.String() || key.GetFromMe() {
		t.Fatalf("key = %+v", key)
	}
	if _, ok := patchOf(msgstore.Pending{Kind: "other", Chat: alice.String()}, time.Now()); ok {
		t.Fatal("unknown kind built")
	}
}

func TestRevokeForEveryone(t *testing.T) {
	s, f, got := sendingSession(t)
	withPhoto(t, s)
	if err := s.RevokeForEveryone(alice.String(), "T1"); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	pm := f.sent[0].GetProtocolMessage()
	if pm.GetType() != waE2E.ProtocolMessage_REVOKE || pm.GetKey().GetID() != "T1" || !pm.GetKey().GetFromMe() || f.to[0] != alice {
		t.Fatalf("sent = %+v to %v", f.sent[0], f.to[0])
	}
	m, _ := s.msgs.Message(context.Background(), alice.String(), "T1")
	if m.Kind != msgstore.KindRevoked || m.Text != "" {
		t.Fatalf("message = %+v", m)
	}
	if typ, data := lastEvent(got); typ != EventDeleted || data["scope"] != ScopeRevoked {
		t.Fatalf("event = %s %v", typ, data)
	}
}

func TestRevokeIsRefused(t *testing.T) {
	s, f, got := sendingSession(t)
	withPhoto(t, s)
	ctx := context.Background()
	old := time.Now().Add(-RevokeWindow - time.Minute).UnixMilli()
	s.msgs.Save(ctx, []msgstore.Message{
		{ChatJID: alice.String(), ID: "OLD", FromMe: true, Kind: msgstore.KindText, Text: "velha", Timestamp: old, Status: msgstore.StatusRead},
		{ChatJID: alice.String(), ID: "FAIL", FromMe: true, Kind: msgstore.KindText, Text: "x", Timestamp: time.Now().UnixMilli(), Status: msgstore.StatusFailed},
	})
	for _, id := range []string{"P1", "OLD", "FAIL", "nope"} { // received, too old, never sent, missing
		if err := s.RevokeForEveryone(alice.String(), id); err == nil {
			t.Fatalf("%s accepted", id)
		}
	}
	f.connected = false
	err := s.RevokeForEveryone(alice.String(), "T1")
	var be *bridge.Error
	if !errors.As(err, &be) || be.Code != CodeOffline {
		t.Fatalf("offline = %v", err)
	}
	if m, _ := s.msgs.Message(ctx, alice.String(), "T1"); m.Kind != msgstore.KindText {
		t.Fatal("changed while offline")
	}
	// WhatsApp refuses: nothing changes and the app is told.
	f.connected = true
	f.sendErr = errors.New("refused")
	s.RevokeForEveryone(alice.String(), "T1")
	s.sends.Wait()
	if typ, _ := lastEvent(got); typ != EventDeleteFailed {
		t.Fatalf("event = %s", typ)
	}
	if m, _ := s.msgs.Message(ctx, alice.String(), "T1"); m.Kind != msgstore.KindText {
		t.Fatal("changed after a refusal")
	}
}

func TestCanRevoke(t *testing.T) {
	now := time.Now()
	mine := msgstore.Message{FromMe: true, Kind: msgstore.KindText, Status: msgstore.StatusDelivered, Timestamp: now.Add(-59 * time.Hour).UnixMilli()}
	if !CanRevoke(mine, now) {
		t.Fatal("59 h refused")
	}
	mine.Timestamp = now.Add(-61 * time.Hour).UnixMilli()
	if CanRevoke(mine, now) {
		t.Fatal("61 h accepted")
	}
}

func revokeEvent(chat types.JID, fromMe bool, id string) *waevents.Message {
	evt := message(chat, &waE2E.Message{ProtocolMessage: &waE2E.ProtocolMessage{
		Type: waE2E.ProtocolMessage_REVOKE.Enum(),
		Key:  &waCommon.MessageKey{ID: proto.String(id), RemoteJID: proto.String(chat.String()), FromMe: proto.Bool(fromMe)},
	}})
	evt.Info.ID = "REVOKER"
	evt.Info.IsFromMe = fromMe
	return evt
}

func TestRevokeFromTheSender(t *testing.T) {
	s, client, got := offlineSession(t)
	withPhoto(t, s)
	// A contact cannot revoke my message.
	s.onMessage(client, revokeEvent(alice, false, "T1"))
	if m, _ := s.msgs.Message(context.Background(), alice.String(), "T1"); m.Kind != msgstore.KindText {
		t.Fatal("revoked by someone else")
	}
	s.onMessage(client, revokeEvent(alice, false, "P1"))
	m, _ := s.msgs.Message(context.Background(), alice.String(), "P1")
	if m.Kind != msgstore.KindRevoked || s.media.Has(vault.Name(alice.String(), "P1", PartFull)) {
		t.Fatalf("message = %+v", m)
	}
	if typ, data := lastEvent(got); typ != EventDeleted || data["scope"] != ScopeRevoked {
		t.Fatalf("event = %s %v", typ, data)
	}
	// From my phone: my own message.
	s.onMessage(client, revokeEvent(alice, true, "T1"))
	if m, _ := s.msgs.Message(context.Background(), alice.String(), "T1"); m.Kind != msgstore.KindRevoked {
		t.Fatal("my revoke from the phone ignored")
	}
	// A protocol message without a type is not a revoke.
	evt := message(alice, &waE2E.Message{ProtocolMessage: &waE2E.ProtocolMessage{Key: &waCommon.MessageKey{ID: proto.String("P1")}}})
	n := len(*got)
	s.onMessage(client, evt)
	if len(*got) != n {
		t.Fatal("untyped protocol message handled")
	}
}

func TestPhoneDeletionsAreMirrored(t *testing.T) {
	s, client, got := offlineSession(t)
	withPhoto(t, s)
	ctx := context.Background()
	s.handle(client, &waevents.DeleteForMe{ChatJID: alice, MessageID: "T1"})
	if page, _ := s.ListMessages(alice.String(), 0, 10); len(page) != 1 {
		t.Fatalf("after delete for me = %+v", page)
	}
	if typ, data := lastEvent(got); typ != EventDeleted || data["id"] != "T1" {
		t.Fatalf("event = %s %v", typ, data)
	}
	s.handle(client, &waevents.ClearChat{JID: alice, Action: &waSyncAction.ClearChatAction{}})
	chats, _ := s.ListChats(10)
	if len(chats) != 1 || chats[0].LastText != "" || s.media.Has(vault.Name(alice.String(), "P1", PartThumb)) {
		t.Fatalf("after clear = %+v", chats)
	}
	if _, data := lastEvent(got); data["scope"] != ScopeClear {
		t.Fatalf("event = %v", data)
	}
	s.msgs.Save(ctx, []msgstore.Message{{ChatJID: alice.String(), ID: "N1", Kind: msgstore.KindText, Text: "nova", Timestamp: 5_000_000}})
	// Deleted on the phone up to a moment: newer messages stay.
	s.handle(client, &waevents.DeleteChat{JID: alice, Action: &waSyncAction.DeleteChatAction{
		MessageRange: &waSyncAction.SyncActionMessageRange{LastMessageTimestamp: proto.Int64(4000)},
	}})
	if page, _ := s.ListMessages(alice.String(), 0, 10); len(page) != 1 {
		t.Fatalf("newer message lost = %+v", page)
	}
	s.handle(client, &waevents.DeleteChat{JID: alice, Action: &waSyncAction.DeleteChatAction{}})
	if chats, _ := s.ListChats(10); len(chats) != 0 {
		t.Fatalf("after delete = %+v", chats)
	}
	if _, data := lastEvent(got); data["scope"] != ScopeChat {
		t.Fatalf("event = %v", data)
	}
	// Nothing is sent back to WhatsApp for deletions made on the phone.
	if p, _ := s.msgs.PendingList(ctx); len(p) != 0 {
		t.Fatalf("queue = %+v", p)
	}
	// A chat that is not here is ignored.
	n := len(*got)
	s.handle(client, &waevents.DeleteChat{JID: bob, Action: &waSyncAction.DeleteChatAction{}})
	if len(*got) != n {
		t.Fatal("event for an unknown chat")
	}
}

func TestDeleteChecksTheChat(t *testing.T) {
	s, _, _ := offlineSession(t)
	if err := s.DeleteChat("not a jid@", false); err == nil {
		t.Fatal("invalid chat accepted")
	}
	var empty Session
	if err := empty.DeleteChat(alice.String(), false); err == nil {
		t.Fatal("accepted before start")
	}
}

func TestDeleteChatAlsoForEveryone(t *testing.T) {
	s, f, got := sendingSession(t)
	revokeGap = time.Millisecond
	t.Cleanup(func() { revokeGap = 500 * time.Millisecond })
	withPhoto(t, s)
	ctx := context.Background()
	now := time.Now()
	var batch []msgstore.Message
	for i := 0; i < MaxRevokeOnDelete+5; i++ {
		batch = append(batch, msgstore.Message{ChatJID: alice.String(), ID: "M" + string(rune('A'+i/26)) + string(rune('a'+i%26)),
			FromMe: true, Kind: msgstore.KindText, Text: "x", Timestamp: now.Add(-time.Duration(i+2) * time.Minute).UnixMilli(), Status: msgstore.StatusRead})
	}
	batch = append(batch,
		msgstore.Message{ChatJID: alice.String(), ID: "OLD", FromMe: true, Kind: msgstore.KindText, Text: "velha", Timestamp: now.Add(-RevokeWindow - time.Hour).UnixMilli(), Status: msgstore.StatusRead},
		msgstore.Message{ChatJID: alice.String(), ID: "FAIL", FromMe: true, Kind: msgstore.KindText, Text: "x", Timestamp: now.UnixMilli() - 500, Status: msgstore.StatusFailed},
	)
	s.msgs.Save(ctx, batch)

	if err := s.DeleteChat(alice.String(), true); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	// The newest 50 of mine, sent and inside the window; never received,
	// old or failed ones.
	if len(f.sent) != MaxRevokeOnDelete {
		t.Fatalf("revoked %d", len(f.sent))
	}
	for _, m := range f.sent {
		id := m.GetProtocolMessage().GetKey().GetID()
		if m.GetProtocolMessage().GetType() != waE2E.ProtocolMessage_REVOKE || id == "OLD" || id == "FAIL" || id == "P1" {
			t.Fatalf("revoked %s", id)
		}
	}
	if f.sent[0].GetProtocolMessage().GetKey().GetID() != "T1" {
		t.Fatalf("newest first, got %s", f.sent[0].GetProtocolMessage().GetKey().GetID())
	}
	typ, data := lastEvent(got)
	if typ != EventRevokeDone || data["revoked"].(float64) != MaxRevokeOnDelete || data["failed"].(float64) != 0 {
		t.Fatalf("event = %s %v", typ, data)
	}
	if len(f.patches) != 1 {
		t.Fatalf("patches = %d", len(f.patches))
	}
	if chats, _ := s.ListChats(10); len(chats) != 0 {
		t.Fatalf("chats = %+v", chats)
	}
}

func TestDeleteChatForEveryoneNeedsTheConnection(t *testing.T) {
	s, f, got := sendingSession(t)
	withPhoto(t, s)
	f.connected = false
	err := s.DeleteChat(alice.String(), true)
	var be *bridge.Error
	if !errors.As(err, &be) || be.Code != CodeOffline {
		t.Fatalf("err = %v", err)
	}
	if chats, _ := s.ListChats(10); len(chats) != 1 {
		t.Fatal("deleted while offline")
	}
	// Refusals are counted.
	f.connected = true
	f.sendErr = errors.New("refused")
	if err := s.DeleteChat(alice.String(), true); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if typ, data := lastEvent(got); typ != EventRevokeDone || data["failed"].(float64) != 1 || data["revoked"].(float64) != 0 {
		t.Fatalf("event = %s %v", typ, data)
	}
}
