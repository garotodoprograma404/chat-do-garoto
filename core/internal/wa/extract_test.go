package wa

import (
	"testing"
	"time"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/msgstore"
)

var (
	alice = types.NewJID("5511900000001", types.DefaultUserServer)
	group = types.NewJID("120363000000000001", types.GroupServer)
)

func message(chat types.JID, m *waE2E.Message) *events.Message {
	return &events.Message{
		Info: types.MessageInfo{
			MessageSource: types.MessageSource{Chat: chat, Sender: alice},
			ID:            "ABC",
			PushName:      "Alice",
			Timestamp:     time.UnixMilli(1_700_000_000_000),
		},
		Message: m,
	}
}

func TestExtractKinds(t *testing.T) {
	cases := []struct {
		name     string
		m        *waE2E.Message
		wantKind string
		wantText string
	}{
		{"conversation", &waE2E.Message{Conversation: proto.String("oi")}, msgstore.KindText, "oi"},
		{"extended", &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{Text: proto.String("com link")}}, msgstore.KindText, "com link"},
		{"image", &waE2E.Message{ImageMessage: &waE2E.ImageMessage{Caption: proto.String("foto")}}, msgstore.KindImage, "foto"},
		{"audio", &waE2E.Message{AudioMessage: &waE2E.AudioMessage{}}, msgstore.KindAudio, ""},
		{"video", &waE2E.Message{VideoMessage: &waE2E.VideoMessage{}}, msgstore.KindVideo, ""},
		{"document", &waE2E.Message{DocumentMessage: &waE2E.DocumentMessage{}}, msgstore.KindDocument, ""},
		{"sticker", &waE2E.Message{StickerMessage: &waE2E.StickerMessage{}}, msgstore.KindSticker, ""},
		{"location", &waE2E.Message{LocationMessage: &waE2E.LocationMessage{}}, msgstore.KindOther, ""},
	}
	for _, c := range cases {
		got, ok := extract(message(group, c.m))
		if !ok || got.Kind != c.wantKind || got.Text != c.wantText {
			t.Errorf("%s: got %+v ok=%v; want kind %s text %q", c.name, got, ok, c.wantKind, c.wantText)
		}
	}
}

func TestExtractFields(t *testing.T) {
	got, ok := extract(message(group, &waE2E.Message{Conversation: proto.String("oi")}))
	if !ok {
		t.Fatal("not extracted")
	}
	want := msgstore.Message{
		ChatJID: group.String(), ID: "ABC", SenderJID: alice.String(), SenderName: "Alice",
		Kind: msgstore.KindText, Text: "oi", Timestamp: 1_700_000_000_000,
	}
	if got != want {
		t.Fatalf("got %+v\nwant %+v", got, want)
	}
}

func TestExtractSkips(t *testing.T) {
	skips := map[string]*events.Message{
		"status":     message(types.StatusBroadcastJID, &waE2E.Message{Conversation: proto.String("story")}),
		"reaction":   message(alice, &waE2E.Message{ReactionMessage: &waE2E.ReactionMessage{Text: proto.String("👍")}}),
		"protocol":   message(alice, &waE2E.Message{ProtocolMessage: &waE2E.ProtocolMessage{}}),
		"key only":   message(group, &waE2E.Message{SenderKeyDistributionMessage: &waE2E.SenderKeyDistributionMessage{}}),
		"no message": message(alice, nil),
	}
	for name, evt := range skips {
		if got, ok := extract(evt); ok {
			t.Errorf("%s: extracted %+v; want skipped", name, got)
		}
	}
}
