package wa

import (
	"context"
	"database/sql"
	"encoding/json"
	"path/filepath"
	"testing"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waCommon"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waHistorySync"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/store/sqlstore"
	"go.mau.fi/whatsmeow/types"
	waevents "go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/events"
	"chatdogaroto/core/internal/msgstore"
)

// offlineSession builds a session with a real (never connected) whatsmeow
// client and a temporary database, recording every emitted event.
func offlineSession(t *testing.T) (*Session, *whatsmeow.Client, *[]map[string]any) {
	s, client, got, _ := offlineSessionWithStore(t)
	return s, client, got
}

func offlineSessionWithStore(t *testing.T) (*Session, *whatsmeow.Client, *[]map[string]any, *sqlstore.Container) {
	t.Helper()
	ctx := context.Background()
	db, err := sql.Open("sqlite3", "file:"+filepath.Join(t.TempDir(), "wa.db")+"?_foreign_keys=on")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	container := sqlstore.NewWithDB(db, "sqlite3", waLog.Noop)
	if err := container.Upgrade(ctx); err != nil {
		t.Fatal(err)
	}
	msgs, err := msgstore.Open(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	device, _ := container.GetFirstDevice(ctx)
	client := whatsmeow.NewClient(device, waLog.Noop)

	var hub events.Hub
	var got []map[string]any
	hub.SetListener(func(b []byte) {
		var e map[string]any
		_ = json.Unmarshal(b, &e)
		got = append(got, e)
	})
	media, err := openVault(ctx, msgs, filepath.Join(t.TempDir(), "media"))
	if err != nil {
		t.Fatal(err)
	}
	return &Session{hub: &hub, client: client, msgs: msgs, media: media}, client, &got, container
}

func webMsg(chat types.JID, id string, ts uint64, text string) *waHistorySync.HistorySyncMsg {
	return &waHistorySync.HistorySyncMsg{Message: &waWeb.WebMessageInfo{
		Key:              &waCommon.MessageKey{RemoteJID: proto.String(chat.String()), ID: proto.String(id), FromMe: proto.Bool(false)},
		Participant:      proto.String(alice.String()), // groups always name the sender
		MessageTimestamp: proto.Uint64(ts),
		Message:          &waE2E.Message{Conversation: proto.String(text)},
	}}
}

func TestHistoryIsStoredWithChatNames(t *testing.T) {
	s, client, got := offlineSession(t)
	s.onHistory(client, &waevents.HistorySync{Data: &waHistorySync.HistorySync{
		Conversations: []*waHistorySync.Conversation{
			{ID: proto.String(group.String()), Name: proto.String("Família"), Messages: []*waHistorySync.HistorySyncMsg{
				webMsg(group, "g1", 100, "bom dia"), webMsg(group, "g2", 200, "tudo bem?"),
			}},
			{ID: proto.String(types.StatusBroadcastJID.String()), Messages: []*waHistorySync.HistorySyncMsg{
				webMsg(types.StatusBroadcastJID, "s1", 300, "story"),
			}},
		},
	}})

	chats, err := s.ListChats(10)
	if err != nil || len(chats) != 1 || chats[0].Name != "Família" || chats[0].LastText != "tudo bem?" {
		t.Fatalf("chats = %+v, err = %v", chats, err)
	}
	msgs, _ := s.ListMessages(group.String(), 0, 10)
	if len(msgs) != 2 || msgs[0].Text != "bom dia" {
		t.Fatalf("messages = %+v", msgs)
	}
	last := (*got)[len(*got)-1]
	if last["type"] != EventHistory || last["data"].(map[string]any)["messages"].(float64) != 2 {
		t.Fatalf("last event = %v", last)
	}
}

func TestLiveMessageStoredOnceAndEmitted(t *testing.T) {
	s, client, got := offlineSession(t)
	evt := message(alice, &waE2E.Message{Conversation: proto.String("oi")})
	evt.Info.Chat = alice

	s.onMessage(client, evt)
	s.onMessage(client, evt) // WhatsApp may deliver the same message again

	if n := len(*got); n != 1 || (*got)[0]["type"] != EventMessage {
		t.Fatalf("events = %v; want one wa_message", *got)
	}
	chats, _ := s.ListChats(10)
	if len(chats) != 1 || chats[0].Name != "Alice" || chats[0].LastText != "oi" {
		t.Fatalf("chats = %+v (name should fall back to the push name)", chats)
	}
	if chats[0].LastFromMe {
		t.Fatal("a message from Alice waits for a reply")
	}
}

func TestMessagesFromAReplacedClientAreIgnored(t *testing.T) {
	s, _, got := offlineSession(t)
	other := whatsmeow.NewClient(s.client.Store, waLog.Noop)
	s.onMessage(other, message(alice, &waE2E.Message{Conversation: proto.String("velho")}))
	if len(*got) != 0 {
		t.Fatalf("events = %v; want none", *got)
	}
}

func TestLIDChatIsNamedAfterItsPhoneNumber(t *testing.T) {
	s, client, _, container := offlineSessionWithStore(t)
	ctx := context.Background()
	client.Store.LIDs = container.LIDMap // a paired device has it
	lid := types.NewJID("28175035842608", types.HiddenUserServer)
	pn := types.NewJID("5511900000009", types.DefaultUserServer)
	if err := client.Store.LIDs.PutLIDMapping(ctx, lid, pn); err != nil {
		t.Fatal(err)
	}
	s.ensureChatName(ctx, client, s.msgs, lid, "")
	if name, _ := s.msgs.ChatName(ctx, lid.String()); name != "5511900000009" {
		t.Fatalf("name = %q, want the phone number", name)
	}
}

func TestPhoneBehindAChat(t *testing.T) {
	s, client, _, container := offlineSessionWithStore(t)
	client.Store.LIDs = container.LIDMap
	lid := types.NewJID("28175035842608", types.HiddenUserServer)
	pn := types.NewJID("5511900000009", types.DefaultUserServer)
	client.Store.LIDs.PutLIDMapping(t.Context(), lid, pn)

	cases := map[string]string{
		"5511900000001@s.whatsapp.net": "5511900000001",
		lid.String():                   "5511900000009",
		"99999999@lid":                 "", // WhatsApp did not tell
		group.String():                 "",
	}
	for chat, want := range cases {
		if got, err := s.PhoneOf(chat); err != nil || got != want {
			t.Errorf("PhoneOf(%s) = %q, %v; want %q", chat, got, err, want)
		}
	}
}

func TestChatForPhone(t *testing.T) {
	s, client, _, container := offlineSessionWithStore(t)
	client.Store.LIDs = container.LIDMap
	ctx := t.Context()
	lid := types.NewJID("28175035842608", types.HiddenUserServer)
	client.Store.LIDs.PutLIDMapping(ctx, lid, types.NewJID("5511900000009", types.DefaultUserServer))
	s.msgs.Save(ctx, []msgstore.Message{
		{ChatJID: "5511900000001@s.whatsapp.net", ID: "1", Kind: msgstore.KindText, Text: "oi", Timestamp: 1},
		{ChatJID: lid.String(), ID: "2", Kind: msgstore.KindText, Text: "oi", Timestamp: 2},
	})

	cases := map[string]string{
		"5511900000001": "5511900000001@s.whatsapp.net",
		"5511900000009": lid.String(), // the chat lives under the LID
		"5511900000005": "",
	}
	for phone, want := range cases {
		if got, err := s.ChatForPhone(phone); err != nil || got != want {
			t.Errorf("ChatForPhone(%s) = %q, %v; want %q", phone, got, err, want)
		}
	}
	if _, err := s.ChatForPhone("55 11"); errCode(err) != "invalid_argument" {
		t.Errorf("non-digits: %v", err)
	}
}
