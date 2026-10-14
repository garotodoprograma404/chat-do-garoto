package wa

import (
	"errors"
	"strings"
	"testing"

	"go.mau.fi/whatsmeow/types"
	waevents "go.mau.fi/whatsmeow/types/events"

	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/msgstore"
)

var me = types.NewJID("5511900000000", types.DefaultUserServer)

func errCode(err error) string {
	var bridgeErr *bridge.Error
	if errors.As(err, &bridgeErr) {
		return bridgeErr.Code
	}
	return ""
}

func eventsOf(got []map[string]any, typ string) []map[string]any {
	var out []map[string]any
	for _, e := range got {
		if e["type"] == typ {
			out = append(out, e["data"].(map[string]any))
		}
	}
	return out
}

func TestSendTextRejectsBadInput(t *testing.T) {
	s, client, _ := offlineSession(t)
	if _, err := s.SendText(alice.String(), "oi"); errCode(err) != "invalid_state" {
		t.Fatalf("unpaired: err = %v, want invalid_state", err)
	}
	client.Store.ID = &me
	for name, c := range map[string][2]string{
		"empty":     {alice.String(), ""},
		"blank":     {alice.String(), "  \n "},
		"too long":  {alice.String(), strings.Repeat("a", maxTextBytes+1)},
		"bad chat":  {"not a jid", "oi"},
		"broadcast": {"status@broadcast", "oi"},
	} {
		if _, err := s.SendText(c[0], c[1]); errCode(err) != bridge.CodeInvalidArgument {
			t.Errorf("%s: err = %v, want invalid_argument", name, err)
		}
	}
}

func TestSendTextOfflineFailsAndRetryUsesTheSameMessage(t *testing.T) {
	s, client, got := offlineSession(t)
	client.Store.ID = &me

	m, err := s.SendText(alice.String(), "olá")
	if err != nil {
		t.Fatal(err)
	}
	if m.Status != msgstore.StatusSending || !m.FromMe || m.ID == "" || m.ChatJID != alice.String() {
		t.Fatalf("returned message = %+v", m)
	}
	s.sends.Wait()

	if live := eventsOf(*got, EventMessage); len(live) != 1 || live[0]["id"] != m.ID {
		t.Fatalf("wa_message events = %v", live)
	}
	statuses := eventsOf(*got, EventMessageStatus)
	if len(statuses) != 1 || statuses[0]["status"] != msgstore.StatusFailed || statuses[0]["chat"] != alice.String() {
		t.Fatalf("status events = %v, want one failed", statuses)
	}

	again, err := s.Retry(alice.String(), m.ID)
	if err != nil || again.ID != m.ID || again.Status != msgstore.StatusSending {
		t.Fatalf("retry = %+v, %v", again, err)
	}
	s.sends.Wait()
	stored, _ := s.msgs.Message(t.Context(), alice.String(), m.ID)
	if stored.Status != msgstore.StatusFailed {
		t.Fatalf("after offline retry: status = %q", stored.Status)
	}
	if n := len(eventsOf(*got, EventMessageStatus)); n != 3 { // failed, sending, failed
		t.Fatalf("status events = %d, want 3", n)
	}
	page, _ := s.ListMessages(alice.String(), 0, 10)
	if len(page) != 1 {
		t.Fatalf("retry duplicated the message: %d stored", len(page))
	}
}

func TestRetryOnlyFailedMessages(t *testing.T) {
	s, client, _ := offlineSession(t)
	client.Store.ID = &me
	s.msgs.Save(t.Context(), []msgstore.Message{
		{ChatJID: alice.String(), ID: "sent", FromMe: true, Kind: msgstore.KindText, Text: "x", Timestamp: 1, Status: msgstore.StatusSent},
		{ChatJID: alice.String(), ID: "theirs", Kind: msgstore.KindText, Text: "x", Timestamp: 2},
	})
	if _, err := s.Retry(alice.String(), "sent"); errCode(err) != "invalid_state" {
		t.Errorf("sent: err = %v", err)
	}
	if _, err := s.Retry(alice.String(), "theirs"); errCode(err) != bridge.CodeInvalidArgument {
		t.Errorf("received: err = %v", err)
	}
	if _, err := s.Retry(alice.String(), "nope"); errCode(err) != bridge.CodeInvalidArgument {
		t.Errorf("missing: err = %v", err)
	}
}

func TestReceiptStatus(t *testing.T) {
	cases := []struct {
		typ    types.ReceiptType
		fromMe bool
		want   string
	}{
		{types.ReceiptTypeDelivered, false, msgstore.StatusDelivered},
		{types.ReceiptTypeRead, false, msgstore.StatusRead},
		{types.ReceiptTypePlayed, false, msgstore.StatusRead},
		{types.ReceiptTypeReadSelf, true, ""},
		{types.ReceiptTypeRead, true, ""}, // my other device
		{types.ReceiptTypeRetry, false, ""},
		{types.ReceiptTypeSender, false, ""},
	}
	for _, c := range cases {
		evt := &waevents.Receipt{Type: c.typ}
		evt.IsFromMe = c.fromMe
		got, ok := receiptStatus(evt)
		if got != c.want || ok != (c.want != "") {
			t.Errorf("%q fromMe=%v: got %q,%v want %q", c.typ, c.fromMe, got, ok, c.want)
		}
	}
}

func TestReceiptsUpdateMyMessages(t *testing.T) {
	s, client, got := offlineSession(t)
	s.msgs.Save(t.Context(), []msgstore.Message{
		{ChatJID: alice.String(), ID: "m1", FromMe: true, Kind: msgstore.KindText, Text: "x", Timestamp: 1, Status: msgstore.StatusSent},
	})
	read := &waevents.Receipt{MessageIDs: []types.MessageID{"m1"}, Type: types.ReceiptTypeRead}
	s.handle(client, read)
	s.handle(client, &waevents.Receipt{MessageIDs: []types.MessageID{"m1"}, Type: types.ReceiptTypeDelivered})

	statuses := eventsOf(*got, EventMessageStatus)
	if len(statuses) != 1 || statuses[0]["status"] != msgstore.StatusRead || statuses[0]["id"] != "m1" {
		t.Fatalf("status events = %v, want only read", statuses)
	}
}
