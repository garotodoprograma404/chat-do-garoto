package msgstore

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
)

func texts(ms []Message) []string {
	var out []string
	for _, m := range ms {
		out = append(out, m.Text)
	}
	return out
}

func TestSearchIgnoresAccentsAndMatchesPrefixes(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{
		msg("a@s", "1", 10, "Segue o orçamento da Ação"),
		msg("b@s", "2", 20, "o ORCAMENTO foi aprovado"),
		msg("a@s", "3", 30, "bom dia"),
		{ChatJID: "a@s", ID: "4", Kind: KindImage, Text: "foto do orçamento", Timestamp: 40},
	})

	got, err := s.Search(ctx, "orç", 10)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"foto do orçamento", "o ORCAMENTO foi aprovado", "Segue o orçamento da Ação"}; len(got) != 3 ||
		got[0].Text != want[0] || got[1].Text != want[1] || got[2].Text != want[2] {
		t.Fatalf("orç = %q, want newest first %q", texts(got), want)
	}
	if got, _ := s.Search(ctx, "acao", 10); len(got) != 1 || got[0].ID != "1" {
		t.Fatalf("acao = %q", texts(got))
	}
	// Every word is required.
	if got, _ := s.Search(ctx, "orcamento aprovado", 10); len(got) != 1 || got[0].ID != "2" {
		t.Fatalf("two words = %q", texts(got))
	}
	if got, _ := s.Search(ctx, "inexistente", 10); len(got) != 0 {
		t.Fatalf("no match = %q", texts(got))
	}
}

func TestSearchIsSafeWithSymbols(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{msg("a@s", "1", 10, `ele disse "oi" AND NOT tchau`)})
	for _, typed := range []string{`"oi"`, `oi AND`, `NOT`, `*`, `(`, `:`, `"`, "   ", ""} {
		if _, err := s.Search(ctx, typed, 10); err != nil {
			t.Errorf("Search(%q): %v", typed, err)
		}
	}
	if got, _ := s.Search(ctx, `"oi"`, 10); len(got) != 1 {
		t.Fatalf(`"oi" = %q`, texts(got))
	}
}

func TestExistingMessagesAreIndexedAndClearEmptiesTheIndex(t *testing.T) {
	ctx := context.Background()
	db, _ := sql.Open("sqlite3", "file:"+filepath.Join(t.TempDir(), "wa.db"))
	defer db.Close()
	// A database as delivery 3.2 left it: schema v4 with messages.
	db.Exec(`CREATE TABLE cc_schema (version INTEGER NOT NULL)`)
	for v := 0; v < 4; v++ {
		if _, err := db.Exec(migrations[v]); err != nil {
			t.Fatal(err)
		}
		db.Exec(`INSERT INTO cc_schema (version) VALUES (?)`, v+1)
	}
	db.Exec(`INSERT INTO cc_messages (chat_jid, id, from_me, kind, text, ts) VALUES ('a@s', '1', 0, 'text', 'mensagem antiga', 10)`)

	s, err := Open(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := s.Search(ctx, "antiga", 10); len(got) != 1 {
		t.Fatalf("old message not indexed: %q", texts(got))
	}
	s.Save(ctx, []Message{msg("a@s", "2", 20, "mensagem nova")})
	if got, _ := s.Search(ctx, "mensagem", 10); len(got) != 2 {
		t.Fatalf("new message not indexed: %q", texts(got))
	}
	s.Clear(ctx)
	if got, _ := s.Search(ctx, "mensagem", 10); len(got) != 0 {
		t.Fatalf("index survived Clear: %q", texts(got))
	}
}
