package msgstore

import (
	"context"
	"database/sql"
	"fmt"
	"path/filepath"
	"testing"

	_ "github.com/WissCore/go-sqlcipher/v4"
)

func open(t *testing.T) *Store {
	t.Helper()
	db, err := sql.Open("sqlite3", "file:"+filepath.Join(t.TempDir(), "wa.db")+"?_foreign_keys=on")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	s, err := Open(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func msg(chat, id string, ts int64, text string) Message {
	return Message{ChatJID: chat, ID: id, Kind: KindText, Text: text, Timestamp: ts}
}

func TestOpenIsIdempotent(t *testing.T) {
	db, _ := sql.Open("sqlite3", "file:"+filepath.Join(t.TempDir(), "wa.db"))
	defer db.Close()
	for i := 0; i < 2; i++ {
		if _, err := Open(context.Background(), db); err != nil {
			t.Fatalf("open #%d: %v", i+1, err)
		}
	}
}

func TestSaveIgnoresDuplicates(t *testing.T) {
	s, ctx := open(t), context.Background()
	added, err := s.Save(ctx, []Message{msg("a@s", "1", 10, "oi"), msg("a@s", "1", 10, "oi"), msg("a@s", "2", 20, "tudo bem?")})
	if err != nil || len(added) != 2 {
		t.Fatalf("added = %d, err = %v; want 2", len(added), err)
	}
	added, _ = s.Save(ctx, []Message{msg("a@s", "2", 20, "tudo bem?")})
	if len(added) != 0 {
		t.Fatalf("re-saving returned %d new messages", len(added))
	}
}

func TestChatsNewestFirstWithPreview(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{
		msg("a@s", "1", 10, "primeira"),
		msg("b@s", "2", 30, "do b"),
		{ChatJID: "a@s", ID: "3", Kind: KindImage, Timestamp: 40},
		msg("a@s", "4", 5, "antiga, chega depois"),
	})
	s.SetChatName(ctx, "a@s", "Ana")

	chats, err := s.ListChats(ctx, 10)
	if err != nil {
		t.Fatal(err)
	}
	want := []Chat{{"a@s", "Ana", "[imagem]", 40, false}, {"b@s", "", "do b", 30, false}}
	if fmt.Sprint(chats) != fmt.Sprint(want) {
		t.Fatalf("chats = %+v\nwant   %+v", chats, want)
	}
}

func TestChatsTellWhetherTheLastMessageIsMine(t *testing.T) {
	s, ctx := open(t), context.Background()
	mine := func(chat, id string, ts int64) Message {
		m := msg(chat, id, ts, "minha")
		m.FromMe = true
		return m
	}
	lastFromMe := func() map[string]bool {
		t.Helper()
		chats, err := s.ListChats(ctx, 10)
		if err != nil {
			t.Fatal(err)
		}
		out := map[string]bool{}
		for _, c := range chats {
			out[c.JID] = c.LastFromMe
		}
		return out
	}
	s.Save(ctx, []Message{msg("a", "1", 10, "oi"), mine("b", "2", 10)})
	if got := lastFromMe(); got["a"] || !got["b"] {
		t.Fatalf("first messages: %v", got)
	}
	// I reply; an older message of theirs arriving later changes nothing.
	s.Save(ctx, []Message{mine("a", "3", 20), msg("a", "4", 15, "antiga")})
	if got := lastFromMe(); !got["a"] {
		t.Fatalf("after my reply: %v", got)
	}
	// They write again.
	s.Save(ctx, []Message{msg("a", "5", 30, "e aí?")})
	if got := lastFromMe(); got["a"] {
		t.Fatalf("after their message: %v", got)
	}
	// Deleting their last message leaves mine as the newest.
	if _, err := s.DeleteMessage(ctx, "a", "5"); err != nil {
		t.Fatal(err)
	}
	if got := lastFromMe(); !got["a"] {
		t.Fatalf("after deleting theirs: %v", got)
	}
	// A cleared chat has nothing to reply to.
	s.Save(ctx, []Message{msg("c", "6", 40, "olá")})
	if _, err := s.ClearChat(ctx, "c", 0); err != nil {
		t.Fatal(err)
	}
	if got := lastFromMe(); !got["c"] {
		t.Fatalf("cleared chat: %v", got)
	}
}

func TestMessagesPagedOldestFirst(t *testing.T) {
	s, ctx := open(t), context.Background()
	var batch []Message
	for i := 1; i <= 120; i++ {
		batch = append(batch, msg("a@s", fmt.Sprint(i), int64(i), fmt.Sprint("m", i)))
	}
	if _, err := s.Save(ctx, batch); err != nil {
		t.Fatal(err)
	}

	page, _ := s.ListMessages(ctx, "a@s", 0, 50)
	if len(page) != 50 || page[0].Timestamp != 71 || page[49].Timestamp != 120 {
		t.Fatalf("first page = %d msgs, %d..%d", len(page), page[0].Timestamp, page[len(page)-1].Timestamp)
	}
	older, _ := s.ListMessages(ctx, "a@s", page[0].Timestamp, 50)
	if len(older) != 50 || older[0].Timestamp != 21 || older[49].Timestamp != 70 {
		t.Fatalf("older page = %d msgs, %d..%d", len(older), older[0].Timestamp, older[len(older)-1].Timestamp)
	}
}

func TestSetChatNameIgnoresEmpty(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.SetChatName(ctx, "a@s", "Ana")
	s.SetChatName(ctx, "a@s", "")
	if name, _ := s.ChatName(ctx, "a@s"); name != "Ana" {
		t.Fatalf("name = %q", name)
	}
}

func TestClearRemovesEverything(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{msg("a@s", "1", 10, "oi")})
	s.SetChatName(ctx, "a@s", "Ana")
	if err := s.Clear(ctx); err != nil {
		t.Fatal(err)
	}
	chats, _ := s.ListChats(ctx, 10)
	msgs, _ := s.ListMessages(ctx, "a@s", 0, 10)
	if name, _ := s.ChatName(ctx, "a@s"); len(chats) != 0 || len(msgs) != 0 || name != "" {
		t.Fatalf("after Clear: %d chats, %d messages, name %q", len(chats), len(msgs), name)
	}
}

func TestChatsWithoutName(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{msg("a@s", "1", 10, "oi"), msg("b@lid", "2", 20, "olá")})
	s.SetChatName(ctx, "a@s", "Ana")
	got, err := s.ChatsWithoutName(ctx)
	if err != nil || len(got) != 1 || got[0] != "b@lid" {
		t.Fatalf("got %v, %v; want [b@lid]", got, err)
	}
}
