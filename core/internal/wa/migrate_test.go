package wa

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"go.mau.fi/whatsmeow/store/sqlstore"
	waLog "go.mau.fi/whatsmeow/util/log"

	"chatdogaroto/core/internal/events"
	"chatdogaroto/core/internal/msgstore"
)

const (
	testKey  = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
	otherKey = "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100"
)

// plainSession writes a wa.db the way deliveries 1.4 to 2.1 did: no key,
// whatsmeow tables, our messages and the connection log.
func plainSession(t *testing.T) string {
	t.Helper()
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "wa", "wa.db")
	os.MkdirAll(filepath.Dir(path), 0o700)
	db, err := sql.Open("sqlite3", "file:"+path+"?_foreign_keys=on&_journal_mode=WAL")
	if err != nil {
		t.Fatal(err)
	}
	if err := sqlstore.NewWithDB(db, "sqlite3", waLog.Noop).Upgrade(ctx); err != nil {
		t.Fatal(err)
	}
	msgs, err := msgstore.Open(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	msgs.Save(ctx, []msgstore.Message{
		{ChatJID: "a@s.whatsapp.net", ID: "1", Kind: msgstore.KindText, Text: "oi", Timestamp: 10},
		{ChatJID: "a@s.whatsapp.net", ID: "2", Kind: msgstore.KindText, Text: "tudo bem?", Timestamp: 20},
	})
	msgs.LogConnection(ctx, 1, msgstore.LogStart, msgstore.SourceApp)
	db.Exec(`PRAGMA user_version = 7`)
	db.Close()
	return path
}

func openEncrypted(t *testing.T, path, key string) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite3", dsn(path, key))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func header(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b[:16])
}

func TestPlainDatabaseIsEncryptedKeepingEverything(t *testing.T) {
	path := plainSession(t)
	if plain, _ := isPlain(path); !plain {
		t.Fatal("fixture is not plain")
	}
	if err := encryptIfPlain(path, testKey); err != nil {
		t.Fatal(err)
	}
	if strings.HasPrefix(header(t, path), "SQLite format 3") {
		t.Fatal("still plain after encrypting")
	}
	for _, leftover := range []string{path + ".enc", path + "-wal", path + "-shm"} {
		if _, err := os.Stat(leftover); err == nil {
			t.Errorf("%s left behind", filepath.Base(leftover))
		}
	}

	db := openEncrypted(t, path, testKey)
	msgs, err := msgstore.Open(context.Background(), db)
	if err != nil {
		t.Fatal(err)
	}
	page, _ := msgs.ListMessages(context.Background(), "a@s.whatsapp.net", 0, 10)
	if len(page) != 2 || page[1].Text != "tudo bem?" {
		t.Fatalf("messages after encrypting = %+v", page)
	}
	var version, devices int
	db.QueryRow(`PRAGMA user_version`).Scan(&version)
	if version != 7 {
		t.Errorf("user_version = %d, want 7", version)
	}
	if err := db.QueryRow(`SELECT COUNT(*) FROM whatsmeow_device`).Scan(&devices); err != nil {
		t.Errorf("whatsmeow tables missing: %v", err)
	}
	if r, _ := msgs.Report(context.Background(), 100); r.Starts[msgstore.SourceApp] != 1 {
		t.Errorf("connection log lost: %+v", r)
	}
	// The search index is rebuilt inside the encrypted database.
	if found, err := msgs.Search(context.Background(), "tudo", 10); err != nil || len(found) != 1 {
		t.Errorf("search after encrypting = %v, %v", found, err)
	}

	// Already encrypted: nothing to do.
	if err := encryptIfPlain(path, testKey); err != nil {
		t.Fatal(err)
	}
}

func TestInterruptedEncryptionStartsOver(t *testing.T) {
	path := plainSession(t)
	// A half-written copy from a run that was cut short.
	os.WriteFile(path+".enc", []byte("partial"), 0o600)

	if err := encryptIfPlain(path, testKey); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := openEncrypted(t, path, testKey).QueryRow(`SELECT COUNT(*) FROM cc_messages`).Scan(&n); err != nil || n != 2 {
		t.Fatalf("messages = %d, %v", n, err)
	}
}

func TestAnotherKeyIsUnreadable(t *testing.T) {
	path := plainSession(t)
	if err := encryptIfPlain(path, testKey); err != nil {
		t.Fatal(err)
	}
	err := openEncrypted(t, path, otherKey).Ping()
	if !isNotADB(err) {
		t.Fatalf("Ping with another key: %v, want not a database", err)
	}

	var hub events.Hub
	s := NewSession(&hub)
	if _, err := s.Resume(path, msgstore.SourceBoot, otherKey); errCode(err) != ErrUnreadable {
		t.Fatalf("Resume with another key: err = %v, want unreadable", err)
	}
	if err := s.Reset(path); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatal("Reset left the database")
	}
}

func TestMalformedKeysAreRefused(t *testing.T) {
	var hub events.Hub
	s := NewSession(&hub)
	for _, key := range []string{"", "abc", strings.ToUpper(testKey), testKey + "00", "x'" + testKey + "'"} {
		_, err := s.Resume(filepath.Join(t.TempDir(), "wa.db"), msgstore.SourceBoot, key)
		if errCode(err) != "invalid_argument" {
			t.Errorf("key %q: err = %v", key, err)
		}
		if err != nil && strings.Contains(err.Error(), testKey) {
			t.Errorf("error echoes the key: %v", err)
		}
	}
}

func TestNewDatabaseIsEncryptedFromTheStart(t *testing.T) {
	var hub events.Hub
	s := NewSession(&hub)
	path := filepath.Join(t.TempDir(), "wa", "wa.db")
	if _, err := s.Resume(path, msgstore.SourceBoot, testKey); err != nil {
		t.Fatal(err)
	}
	if strings.HasPrefix(header(t, path), "SQLite format 3") {
		t.Fatal("a new wa.db is plain")
	}
}

// Every connection of wa.db zeroes what is deleted.
func TestEveryConnectionZeroesDeletes(t *testing.T) {
	db := openEncrypted(t, filepath.Join(t.TempDir(), "wa.db"), testKey)
	db.SetMaxOpenConns(3)
	conns := make([]*sql.Conn, 3)
	for i := range conns {
		c, err := db.Conn(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		defer c.Close()
		conns[i] = c
	}
	for i, c := range conns {
		var on int
		if err := c.QueryRowContext(context.Background(), `PRAGMA secure_delete`).Scan(&on); err != nil || on != 1 {
			t.Fatalf("connection %d: secure_delete=%d err=%v", i, on, err)
		}
	}
}
