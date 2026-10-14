package msgstore

import (
	"context"
	"database/sql"
	"path/filepath"
	"slices"
	"testing"
)

func mine(chat, id string, status string) Message {
	return Message{ChatJID: chat, ID: id, FromMe: true, Kind: KindText, Text: "x", Timestamp: 10, Status: status}
}

func status(t *testing.T, s *Store, chat, id string) string {
	t.Helper()
	m, err := s.Message(context.Background(), chat, id)
	if err != nil {
		t.Fatal(err)
	}
	return m.Status
}

func TestMigratesV1DatabaseKeepingData(t *testing.T) {
	ctx := context.Background()
	db, _ := sql.Open("sqlite3", "file:"+filepath.Join(t.TempDir(), "wa.db"))
	defer db.Close()
	// A database as delivery 1.5 left it: schema v1 with messages.
	db.Exec(`CREATE TABLE cc_schema (version INTEGER NOT NULL)`)
	db.Exec(migrations[0])
	db.Exec(`INSERT INTO cc_schema (version) VALUES (1)`)
	db.Exec(`INSERT INTO cc_messages (chat_jid, id, from_me, kind, text, ts) VALUES ('a@s', '1', 0, 'text', 'oi', 10)`)

	s, err := Open(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	m, err := s.Message(ctx, "a@s", "1")
	if err != nil || m.Text != "oi" || m.Status != "" {
		t.Fatalf("message after migration = %+v, %v", m, err)
	}
	var version int
	db.QueryRow(`SELECT MAX(version) FROM cc_schema`).Scan(&version)
	if version != len(migrations) {
		t.Fatalf("schema version = %d, want %d", version, len(migrations))
	}
}

func TestStatusOnlyMovesForward(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{mine("a@s", "1", StatusSending)})

	steps := []struct {
		to      string
		changed bool
		want    string
	}{
		{StatusDelivered, true, StatusDelivered}, // receipt before the send returns
		{StatusSent, false, StatusDelivered},
		{StatusFailed, false, StatusDelivered},
		{StatusRead, true, StatusRead},
		{StatusDelivered, false, StatusRead},
		{StatusSending, false, StatusRead},
	}
	for _, st := range steps {
		chats, err := s.SetStatus(ctx, "1", st.to)
		if err != nil {
			t.Fatal(err)
		}
		if got := len(chats) > 0; got != st.changed {
			t.Errorf("SetStatus(%s): changed = %v, want %v", st.to, got, st.changed)
		}
		if got := status(t, s, "a@s", "1"); got != st.want {
			t.Errorf("after %s: status = %q, want %q", st.to, got, st.want)
		}
	}
}

func TestFailedCanBeRetriedOrStillDelivered(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{mine("a@s", "1", StatusSending), mine("a@s", "2", StatusSending)})

	if chats, _ := s.SetStatus(ctx, "1", StatusFailed); !slices.Equal(chats, []string{"a@s"}) {
		t.Fatalf("fail: chats = %v", chats)
	}
	if chats, _ := s.SetStatus(ctx, "1", StatusSending); len(chats) != 1 {
		t.Fatal("retry did not turn failed into sending")
	}
	s.SetStatus(ctx, "2", StatusFailed)
	if chats, _ := s.SetStatus(ctx, "2", StatusDelivered); len(chats) != 1 {
		t.Fatal("a receipt after failed must count: the message arrived")
	}
}

func TestReceiptsReachMessagesSentFromThePhoneButNotReceivedOnes(t *testing.T) {
	s, ctx := open(t), context.Background()
	theirs := msg("a@s", "2", 20, "deles")
	s.Save(ctx, []Message{mine("a@s", "1", ""), theirs})

	if chats, _ := s.SetStatus(ctx, "1", StatusRead); len(chats) != 1 {
		t.Fatal("my message sent from the phone did not take the receipt")
	}
	if chats, _ := s.SetStatus(ctx, "2", StatusRead); len(chats) != 0 {
		t.Fatal("a received message got a status")
	}
	if _, err := s.SetStatus(ctx, "1", "bogus"); err == nil {
		t.Fatal("unknown status accepted")
	}
}

func TestFailPendingAndMessageNotFound(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{mine("a@s", "1", StatusSending), mine("a@s", "2", StatusSent)})

	if err := s.FailPending(ctx); err != nil {
		t.Fatal(err)
	}
	if got := status(t, s, "a@s", "1"); got != StatusFailed {
		t.Errorf("pending = %q, want failed", got)
	}
	if got := status(t, s, "a@s", "2"); got != StatusSent {
		t.Errorf("sent changed to %q", got)
	}
	if _, err := s.Message(ctx, "a@s", "nope"); err != ErrNotFound {
		t.Fatalf("err = %v, want ErrNotFound", err)
	}
	page, _ := s.ListMessages(ctx, "a@s", 0, 10)
	if len(page) != 2 || page[0].Status == "" {
		t.Fatalf("listed messages lack status: %+v", page)
	}
}
