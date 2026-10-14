package msgstore

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"
	"strings"
)

// SchemaVersion is the version of the cc_* tables this code writes; a
// backup with a newer one is refused.
func SchemaVersion() int { return len(migrations) }

// restored lists the tables a backup brings back, in an order that keeps
// references valid. The connection log, the deletion queue and the search
// index stay with this device (the index is rebuilt by the triggers).
var restored = []string{"cc_chats", "cc_messages", "cc_media", "cc_settings"}

var hexKey = regexp.MustCompile(`^[0-9a-f]{64}$`)

// attach attaches the database at path, encrypted with key, as bk on conn.
func attach(ctx context.Context, conn *sql.Conn, path, key string) error {
	if !hexKey.MatchString(key) {
		return fmt.Errorf("msgstore: malformed backup key") // never echo it
	}
	_, err := conn.ExecContext(ctx, fmt.Sprintf(`ATTACH DATABASE '%s' AS bk KEY "x'%s'"`,
		strings.ReplaceAll(path, "'", "''"), key))
	return err
}

// ExportTo copies the conversations (the restored tables) to a new
// database at path, encrypted with the one-time key. The copy
// is created empty at this version, so the WhatsApp session, the search
// index, the connection log and the deletion queue never enter it; open
// must open it with key.
func (s *Store) ExportTo(ctx context.Context, path, key string, open func(path, key string) (*sql.DB, error)) error {
	if !hexKey.MatchString(key) {
		return fmt.Errorf("msgstore: malformed backup key") // never echo it
	}
	copyDB, err := open(path, key)
	if err != nil {
		return err
	}
	_, err = Open(ctx, copyDB)
	if err == nil {
		_, err = copyDB.ExecContext(ctx, `DROP TRIGGER cc_messages_fts_bd; DROP TRIGGER cc_messages_fts_bu;
			DROP TRIGGER cc_messages_fts_ai; DROP TRIGGER cc_messages_fts_au; DROP TABLE cc_messages_fts;`)
	}
	copyDB.Close()
	if err != nil {
		return err
	}
	conn, err := s.db.Conn(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err := attach(ctx, conn, path, key); err != nil {
		return err
	}
	defer conn.ExecContext(context.Background(), `DETACH DATABASE bk`)
	tx, err := conn.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, t := range restored {
		if err := copyRows(ctx, tx, t, "main", "bk"); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// copyRows copies every row of table from schema "from" to schema "to".
func copyRows(ctx context.Context, tx *sql.Tx, table, from, to string) error {
	cols, err := columns(ctx, tx, table)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, fmt.Sprintf(`INSERT INTO %s.%s (%s) SELECT %s FROM %s.%s`,
		to, table, cols, cols, from, table))
	return err
}

// ImportFrom replaces the cc_* data with the copy at path (from ExportTo,
// encrypted with key), in one transaction. An older copy is
// brought up to this version first; open must open it with key.
func (s *Store) ImportFrom(ctx context.Context, path, key string, open func(path, key string) (*sql.DB, error)) error {
	copyDB, err := open(path, key)
	if err != nil {
		return err
	}
	_, err = Open(ctx, copyDB) // migrations of an older backup
	copyDB.Close()
	if err != nil {
		return err
	}
	conn, err := s.db.Conn(ctx)
	if err != nil {
		return err
	}
	defer conn.Close()
	if err := attach(ctx, conn, path, key); err != nil {
		return err
	}
	defer conn.ExecContext(context.Background(), `DETACH DATABASE bk`)
	tx, err := conn.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for i := len(restored) - 1; i >= 0; i-- {
		if _, err := tx.ExecContext(ctx, `DELETE FROM main.`+restored[i]); err != nil {
			return err
		}
	}
	for _, t := range restored {
		if err := copyRows(ctx, tx, t, "bk", "main"); err != nil {
			return err
		}
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	return s.compact(ctx)
}

// columns lists the columns of main.table, quoted, for copying rows.
func columns(ctx context.Context, tx *sql.Tx, table string) (string, error) {
	rows, err := tx.QueryContext(ctx, `SELECT name FROM pragma_table_info(?, 'main')`, table)
	if err != nil {
		return "", err
	}
	defer rows.Close()
	var names []string
	for rows.Next() {
		var n string
		if err := rows.Scan(&n); err != nil {
			return "", err
		}
		names = append(names, `"`+n+`"`)
	}
	if len(names) == 0 {
		return "", fmt.Errorf("msgstore: table %s not found", table)
	}
	return strings.Join(names, ", "), rows.Err()
}

// ForgetMedia marks every media as not downloaded, for a backup restored
// without them: those WhatsApp still has can be downloaded
// again; a media of mine never uploaded is gone.
func (s *Store) ForgetMedia(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE cc_media SET thumb = 0,
		 state = CASE WHEN length(proto) > 0 AND state != ? THEN ? ELSE ? END`,
		MediaExpired, MediaRemote, MediaExpired)
	return err
}
