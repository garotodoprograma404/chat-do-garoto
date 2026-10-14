package msgstore

import (
	"bytes"
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
)

func withMedia(t *testing.T, s *Store, chat, id string) {
	t.Helper()
	if err := s.SaveMedia(context.Background(), MediaRecord{
		ChatJID: chat, ID: id, Kind: KindImage, State: MediaDownloaded, Proto: []byte("key"),
	}); err != nil {
		t.Fatal(err)
	}
}

func TestDeleteChat(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.Save(ctx, []Message{
		msg("a", "1", 10, "primeira"),
		{ChatJID: "a", ID: "2", Kind: KindImage, Text: "foto", Timestamp: 20},
		msg("b", "3", 30, "outra conversa"),
	})
	withMedia(t, s, "a", "2")
	s.AddPending(ctx, Pending{Kind: PendingDeleteForMe, Chat: "x", ID: "9"})

	ids, err := s.DeleteChat(ctx, "a", 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != 1 || ids[0] != "2" {
		t.Fatalf("media to delete = %v", ids)
	}
	chats, _ := s.ListChats(ctx, 10)
	if len(chats) != 1 || chats[0].JID != "b" {
		t.Fatalf("chats = %+v", chats)
	}
	if _, err := s.Media(ctx, "a", "2"); err != ErrNotFound {
		t.Fatalf("media record left: %v", err)
	}
	if found, _ := s.Search(ctx, "primeira", 10); len(found) != 0 {
		t.Fatalf("search still finds it: %+v", found)
	}
	// A new message brings the chat back with only itself.
	s.Save(ctx, []Message{msg("a", "4", 40, "nova")})
	page, _ := s.ListMessages(ctx, "a", 0, 10)
	if len(page) != 1 || page[0].ID != "4" {
		t.Fatalf("after a new message = %+v", page)
	}
	// The queue is untouched by deletions.
	if p, _ := s.PendingList(ctx); len(p) != 1 {
		t.Fatalf("pending = %+v", p)
	}
}

func TestDeleteChatUpToKeepsNewer(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.Save(ctx, []Message{msg("a", "1", 10, "velha"), msg("a", "2", 20, "nova")})
	if _, err := s.DeleteChat(ctx, "a", 10); err != nil {
		t.Fatal(err)
	}
	chats, _ := s.ListChats(ctx, 10)
	if len(chats) != 1 || chats[0].LastText != "nova" {
		t.Fatalf("chats = %+v", chats)
	}
}

func TestClearChatKeepsItEmpty(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.Save(ctx, []Message{msg("a", "1", 10, "oi")})
	s.SetChatName(ctx, "a", "Ana")
	if _, err := s.ClearChat(ctx, "a", 0); err != nil {
		t.Fatal(err)
	}
	chats, _ := s.ListChats(ctx, 10)
	if len(chats) != 1 || chats[0].LastText != "" || chats[0].Name != "Ana" {
		t.Fatalf("chats = %+v", chats)
	}
	if page, _ := s.ListMessages(ctx, "a", 0, 10); len(page) != 0 {
		t.Fatalf("messages left = %+v", page)
	}
}

func TestDeleteMessage(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.Save(ctx, []Message{
		msg("a", "1", 10, "fica"),
		{ChatJID: "a", ID: "2", Kind: KindImage, Text: "sai", Timestamp: 20},
	})
	withMedia(t, s, "a", "2")
	had, err := s.DeleteMessage(ctx, "a", "2")
	if err != nil || !had {
		t.Fatalf("had=%v err=%v", had, err)
	}
	chats, _ := s.ListChats(ctx, 10)
	if chats[0].LastText != "fica" || chats[0].LastTS != 10 {
		t.Fatalf("chat = %+v", chats[0])
	}
	if had, err := s.DeleteMessage(ctx, "a", "nope"); err != nil || had {
		t.Fatalf("missing: had=%v err=%v", had, err)
	}
}

func TestRevoke(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.Save(ctx, []Message{
		{ChatJID: "a", ID: "1", Kind: KindImage, Text: "segredo", Timestamp: 10, Forwarded: true},
		{ChatJID: "a", ID: "2", FromMe: true, Kind: KindText, Text: "minha", Timestamp: 20},
	})
	withMedia(t, s, "a", "1")
	m, had, err := s.Revoke(ctx, "a", "1")
	if err != nil || !had {
		t.Fatalf("had=%v err=%v", had, err)
	}
	if m.Kind != KindRevoked || m.Text != "" || m.Media != "" || m.Forwarded {
		t.Fatalf("revoked = %+v", m)
	}
	if found, _ := s.Search(ctx, "segredo", 10); len(found) != 0 {
		t.Fatalf("search still finds it")
	}
	s.Revoke(ctx, "a", "2")
	chats, _ := s.ListChats(ctx, 10)
	if chats[0].LastText != "Você apagou esta mensagem" {
		t.Fatalf("preview = %q", chats[0].LastText)
	}
	if _, _, err := s.Revoke(ctx, "a", "nope"); err != ErrNotFound {
		t.Fatalf("missing = %v", err)
	}
}

func TestChatOf(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.Save(ctx, []Message{msg("lid", "1", 10, "oi")})
	if c, _ := s.ChatOf(ctx, "1", "pn", "lid"); c != "lid" {
		t.Fatalf("chat = %q", c)
	}
	if c, _ := s.ChatOf(ctx, "1", "pn"); c != "" {
		t.Fatalf("chat = %q", c)
	}
}

func TestPendingQueue(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.AddPending(ctx, Pending{Kind: PendingDeleteChat, Chat: "a", ID: "1", FromMe: true, TS: 10})
	s.AddPending(ctx, Pending{Kind: PendingDeleteForMe, Chat: "b", ID: "2", TS: 20})
	p, err := s.PendingList(ctx)
	if err != nil || len(p) != 2 || p[0].Kind != PendingDeleteChat || !p[0].FromMe || p[1].ID != "2" {
		t.Fatalf("pending = %+v err=%v", p, err)
	}
	s.DonePending(ctx, p[0].Seq)
	if p, _ := s.PendingList(ctx); len(p) != 1 || p[0].Chat != "b" {
		t.Fatalf("after done = %+v", p)
	}
	s.Clear(ctx)
	if p, _ := s.PendingList(ctx); len(p) != 0 {
		t.Fatalf("after clear = %+v", p)
	}
}

// What is deleted is not left in the database file, in the journal or
// in the search index. A plain database lets the test read the raw bytes;
// the real one is the same, encrypted.
func TestDeletedTextLeavesNoTrace(t *testing.T) {
	for _, tc := range []struct {
		name   string
		delete func(*Store) error
	}{
		{"chat", func(s *Store) error { _, err := s.DeleteChat(context.Background(), "a", 0); return err }},
		{"message", func(s *Store) error { _, err := s.DeleteMessage(context.Background(), "a", "1"); return err }},
		{"revoke", func(s *Store) error { _, _, err := s.Revoke(context.Background(), "a", "1"); return err }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "wa.db")
			db, err := sql.Open("sqlite3", "file:"+path+"?_journal_mode=WAL&_secure_delete=on")
			if err != nil {
				t.Fatal(err)
			}
			defer db.Close()
			ctx := context.Background()
			s, err := Open(ctx, db)
			if err != nil {
				t.Fatal(err)
			}
			const secret = "zebracadabraxyz"
			var batch []Message
			for i := 0; i < 50; i++ { // enough rows to span pages and index segments
				batch = append(batch, msg("b", string(rune('A'+i%26))+string(rune('a'+i/26)), int64(i), "texto comum numero"))
			}
			batch = append(batch, msg("a", "1", 100, "o "+secret+" aqui"))
			if _, err := s.Save(ctx, batch); err != nil {
				t.Fatal(err)
			}
			db.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`)
			if !contains(t, path, secret) {
				t.Fatal("the test cannot see the text before deleting")
			}
			if err := tc.delete(s); err != nil {
				t.Fatal(err)
			}
			if contains(t, path, secret) || contains(t, path+"-wal", secret) {
				t.Fatal("deleted text left in the file or journal")
			}
			// Half of the word (a search prefix) is not left either.
			if contains(t, path, secret[:8]) || contains(t, path+"-wal", secret[:8]) {
				t.Fatal("index terms left")
			}
		})
	}
}

func contains(t *testing.T, path, word string) bool {
	t.Helper()
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return false
	}
	if err != nil {
		t.Fatal(err)
	}
	return bytes.Contains(data, []byte(word))
}
