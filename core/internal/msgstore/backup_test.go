package msgstore

import (
	"context"
	"database/sql"
	"path/filepath"
	"strings"
	"testing"
)

const copyKey = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

func openCopy(path, key string) (*sql.DB, error) {
	return sql.Open("sqlite3", "file:"+path+"?_pragma_key=x'"+key+"'")
}

// withSession adds a table like whatsmeow's session tables.
func withSession(t *testing.T, s *Store) {
	t.Helper()
	if _, err := s.db.Exec(`CREATE TABLE whatsmeow_device (jid TEXT, identity BLOB);
		INSERT INTO whatsmeow_device VALUES ('5511900000000@s.whatsapp.net', x'0102')`); err != nil {
		t.Fatal(err)
	}
}

func tables(t *testing.T, db *sql.DB) []string {
	t.Helper()
	rows, err := db.Query(`SELECT name FROM sqlite_master WHERE type IN ('table', 'trigger') ORDER BY name`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var n string
		rows.Scan(&n)
		out = append(out, n)
	}
	return out
}

func exported(t *testing.T) (string, *Store) {
	t.Helper()
	s := open(t)
	ctx := context.Background()
	withSession(t, s)
	s.Save(ctx, []Message{msg("a", "1", 10, "orçamento aprovado"), msg("b", "2", 20, "oi")})
	s.SetChatName(ctx, "a", "Ana")
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a", ID: "1", Kind: KindImage, State: MediaDownloaded, Thumb: true, Proto: []byte("k")})
	s.SetSetting(ctx, "vault_identity", "AGE-SECRET-KEY-TESTE")
	s.LogConnection(ctx, 1, LogStart, SourceApp)
	s.AddPending(ctx, Pending{Kind: PendingDeleteChat, Chat: "x"})
	path := filepath.Join(t.TempDir(), "wa.db")
	if err := s.ExportTo(ctx, path, copyKey, openCopy); err != nil {
		t.Fatal(err)
	}
	return path, s
}

// The copy has the conversations but not the WhatsApp session.
func TestExportLeavesTheSessionOut(t *testing.T) {
	path, _ := exported(t)
	db, _ := openCopy(path, copyKey)
	defer db.Close()
	names := strings.Join(tables(t, db), " ")
	if strings.Contains(names, "whatsmeow") || strings.Contains(names, "fts") {
		t.Fatalf("tables = %s", names)
	}
	var n int
	db.QueryRow(`SELECT COUNT(*) FROM cc_messages`).Scan(&n)
	if n != 2 {
		t.Fatalf("messages = %d", n)
	}
	for _, q := range []string{`SELECT COUNT(*) FROM cc_connection_log`, `SELECT COUNT(*) FROM cc_pending_sync`} {
		db.QueryRow(q).Scan(&n)
		if n != 0 {
			t.Fatalf("%s = %d", q, n)
		}
	}
	// Without the one-time key the copy does not open.
	plain, _ := sql.Open("sqlite3", "file:"+path)
	defer plain.Close()
	if _, err := plain.Exec(`SELECT COUNT(*) FROM sqlite_master`); err == nil {
		t.Fatal("copy readable without the key")
	}
	if !contains(t, path, "x") || contains(t, path, "orçamento") || contains(t, path, "5511900000000") {
		t.Fatal("readable content in the copy")
	}
}

func TestImportReplaces(t *testing.T) {
	path, _ := exported(t)
	ctx := context.Background()
	s := open(t)
	withSession(t, s)
	s.Save(ctx, []Message{msg("z", "9", 5, "deste aparelho")})
	s.LogConnection(ctx, 2, LogStart, SourceApp)
	if err := s.ImportFrom(ctx, path, copyKey, openCopy); err != nil {
		t.Fatal(err)
	}
	chats, _ := s.ListChats(ctx, 10)
	if len(chats) != 2 || chats[1].Name != "Ana" {
		t.Fatalf("chats = %+v", chats)
	}
	if found, _ := s.Search(ctx, "orcamento", 10); len(found) != 1 {
		t.Fatalf("search after restore = %+v", found)
	}
	if found, _ := s.Search(ctx, "aparelho", 10); len(found) != 0 {
		t.Fatal("old messages left in the index")
	}
	if id, _ := s.Setting(ctx, "vault_identity"); id != "AGE-SECRET-KEY-TESTE" {
		t.Fatalf("identity = %q", id)
	}
	m, _ := s.Message(ctx, "a", "1")
	if m.Media != MediaDownloaded || !m.Thumb {
		t.Fatalf("media = %+v", m)
	}
	// The session and the connection log of this device stay.
	var n int
	s.db.QueryRow(`SELECT COUNT(*) FROM whatsmeow_device`).Scan(&n)
	if n != 1 {
		t.Fatal("session lost")
	}
	s.db.QueryRow(`SELECT COUNT(*) FROM cc_connection_log`).Scan(&n)
	if n != 1 {
		t.Fatalf("log = %d", n)
	}
	// Messages arriving after the restore join without duplicates.
	added, _ := s.Save(ctx, []Message{msg("a", "1", 10, "orçamento aprovado"), msg("a", "3", 30, "nova")})
	if len(added) != 1 {
		t.Fatalf("added = %+v", added)
	}
}

// A copy from an older version is brought up to date.
func TestImportOlderCopy(t *testing.T) {
	path, _ := exported(t)
	db, _ := openCopy(path, copyKey)
	if _, err := db.Exec(`DROP TABLE cc_pending_sync; DELETE FROM cc_schema WHERE version = 7`); err != nil {
		t.Fatal(err)
	}
	db.Close()
	s := open(t)
	if err := s.ImportFrom(context.Background(), path, copyKey, openCopy); err != nil {
		t.Fatal(err)
	}
	if chats, _ := s.ListChats(context.Background(), 10); len(chats) != 2 {
		t.Fatalf("chats = %+v", chats)
	}
}

func TestForgetMedia(t *testing.T) {
	s := open(t)
	ctx := context.Background()
	s.Save(ctx, []Message{msg("a", "1", 10, ""), msg("a", "2", 20, ""), msg("a", "3", 30, "")})
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a", ID: "1", Kind: KindImage, State: MediaDownloaded, Thumb: true, Proto: []byte("k")})
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a", ID: "2", Kind: KindImage, State: MediaDownloaded}) // never uploaded
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a", ID: "3", Kind: KindImage, State: MediaExpired, Proto: []byte("k")})
	if err := s.ForgetMedia(ctx); err != nil {
		t.Fatal(err)
	}
	for id, want := range map[string]string{"1": MediaRemote, "2": MediaExpired, "3": MediaExpired} {
		m, _ := s.Message(ctx, "a", id)
		if m.Media != want || m.Thumb {
			t.Fatalf("%s = %+v", id, m)
		}
	}
}

func TestBadKeyIsRefused(t *testing.T) {
	s := open(t)
	if err := s.ExportTo(context.Background(), filepath.Join(t.TempDir(), "x.db"), "x'; DROP", openCopy); err == nil {
		t.Fatal("malformed key accepted")
	}
}
