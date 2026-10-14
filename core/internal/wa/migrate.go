package wa

import (
	"bytes"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"regexp"

	sqlite3 "github.com/WissCore/go-sqlcipher/v4"

	"chatdogaroto/core/internal/bridge"
)

// ErrUnreadable is returned when the key does not open wa.db: the app then deletes the session and pairs again.
const ErrUnreadable = "unreadable"

var hexKey = regexp.MustCompile(`^[0-9a-f]{64}$`)

// plainHeader starts every SQLite file that is not encrypted.
var plainHeader = []byte("SQLite format 3\x00")

func validateKey(key string) error {
	if !hexKey.MatchString(key) {
		// Never echo the key back.
		return &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "key must be 64 lowercase hex digits"}
	}
	return nil
}

func unreadable() error {
	return &bridge.Error{Code: ErrUnreadable, Message: "the key does not open the session database"}
}

// isNotADB reports whether err is SQLite's "file is not a database", which
// SQLCipher returns for a wrong key.
func isNotADB(err error) bool {
	var e sqlite3.Error
	return errors.As(err, &e) && e.Code == sqlite3.ErrNotADB
}

// dsn opens path with key applied to every connection of the pool. It holds
// the key: never log it.
func dsn(path, key string) string {
	return "file:" + path + "?_pragma_key=x'" + key +
		"'&_foreign_keys=on&_busy_timeout=10000&_journal_mode=WAL&_secure_delete=on"
}

// isPlain reports whether path is an unencrypted SQLite database.
func isPlain(path string) (bool, error) {
	f, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	defer f.Close()
	header := make([]byte, len(plainHeader))
	if _, err := io.ReadFull(f, header); err != nil {
		return false, nil // empty or tiny file: not a plain database
	}
	return bytes.Equal(header, plainHeader), nil
}

// encryptIfPlain converts an unencrypted wa.db (deliveries 1.4 to 2.1) into
// an encrypted one with key, keeping every table. The plain
// file is only replaced once the encrypted copy is complete and checked, so
// an interrupted run simply starts over.
func encryptIfPlain(path, key string) error {
	tmp := path + ".enc"
	removeFiles(tmp, tmp+"-journal", tmp+"-wal", tmp+"-shm") // leftovers of an interrupted run
	plain, err := isPlain(path)
	if err != nil || !plain {
		return err
	}

	db, err := sql.Open("sqlite3", "file:"+path+"?_busy_timeout=10000")
	if err != nil {
		return err
	}
	db.SetMaxOpenConns(1) // ATTACH is per connection
	if err := export(db, tmp, key); err != nil {
		db.Close()
		removeFiles(tmp, tmp+"-journal")
		return fmt.Errorf("encrypting the session database: %w", err)
	}
	if err := db.Close(); err != nil {
		return err
	}
	// The plain database is closed and fully checkpointed: drop its WAL
	// files first, then put the encrypted copy in its place (atomic rename).
	removeFiles(path+"-wal", path+"-shm")
	return os.Rename(tmp, path)
}

// export copies the open plain database into an encrypted file at tmp.
func export(db *sql.DB, tmp, key string) error {
	if _, err := db.Exec(`PRAGMA wal_checkpoint(TRUNCATE)`); err != nil {
		return err
	}
	// sqlcipher_export does not copy virtual tables: drop the message search
	// index; msgstore.Open builds it again, encrypted, when it is
	// missing.
	if _, err := db.Exec(`
		DROP TRIGGER IF EXISTS cc_messages_fts_bd;
		DROP TRIGGER IF EXISTS cc_messages_fts_bu;
		DROP TRIGGER IF EXISTS cc_messages_fts_ai;
		DROP TRIGGER IF EXISTS cc_messages_fts_au;
		DROP TABLE IF EXISTS cc_messages_fts;`); err != nil {
		return err
	}
	if _, err := db.Exec(`ATTACH DATABASE ? AS enc KEY ?`, tmp, "x'"+key+"'"); err != nil {
		return err
	}
	if _, err := db.Exec(`SELECT sqlcipher_export('enc')`); err != nil {
		return err
	}
	var version int
	if err := db.QueryRow(`PRAGMA main.user_version`).Scan(&version); err != nil {
		return err
	}
	if _, err := db.Exec(fmt.Sprintf(`PRAGMA enc.user_version = %d`, version)); err != nil {
		return err
	}
	if err := sameRows(db); err != nil {
		return err
	}
	_, err := db.Exec(`DETACH DATABASE enc`)
	return err
}

// sameRows checks that every table has as many rows in the copy.
func sameRows(db *sql.DB) error {
	rows, err := db.Query(`SELECT name FROM main.sqlite_master
		WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND sql NOT LIKE 'CREATE VIRTUAL TABLE%'`)
	if err != nil {
		return err
	}
	var tables []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			rows.Close()
			return err
		}
		tables = append(tables, name)
	}
	rows.Close()
	for _, t := range tables {
		var a, b int64
		q := `SELECT (SELECT COUNT(*) FROM main."` + t + `"), (SELECT COUNT(*) FROM enc."` + t + `")`
		if err := db.QueryRow(q).Scan(&a, &b); err != nil {
			return err
		}
		if a != b {
			return fmt.Errorf("table %s: %d rows, copy has %d", t, a, b)
		}
	}
	return nil
}

func removeFiles(paths ...string) {
	for _, p := range paths {
		_ = os.Remove(p)
	}
}

// Reset deletes the session database files without opening them, after
// they turned unreadable.
func (s *Session) Reset(dbPath string) error {
	s.mu.Lock()
	open := s.client != nil
	s.mu.Unlock()
	if open {
		return invalidState("stop the session first")
	}
	removeFiles(dbPath, dbPath+"-wal", dbPath+"-shm", dbPath+"-journal", dbPath+".enc", dbPath+".enc-journal")
	return nil
}
