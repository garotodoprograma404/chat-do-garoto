package msgstore

import (
	"context"
	"database/sql"
)

// KindRevoked is a message deleted for everyone: its content is
// gone, only the bubble is left ("Mensagem apagada").
const KindRevoked = "revoked"

// Pending WhatsApp updates of deletions made here, sent when
// connected.
const (
	PendingDeleteChat  = "delete_chat"
	PendingDeleteForMe = "delete_for_me"
)

// Pending is a deletion still to be sent to WhatsApp. It only holds
// identifiers, never content.
type Pending struct {
	Seq    int64
	Kind   string
	Chat   string
	ID     string // the message, or the chat's last message
	FromMe bool
	Sender string // who sent the message (groups)
	TS     int64  // Unix milliseconds
}

// Newest returns the newest stored message of a chat, or ErrNotFound.
func (s *Store) Newest(ctx context.Context, chat string) (Message, error) {
	m, err := scanMessage(s.db.QueryRowContext(ctx,
		`SELECT `+messageColumns+` FROM cc_messages m
		 LEFT JOIN cc_media d ON d.chat_jid = m.chat_jid AND d.id = m.id
		 WHERE m.chat_jid = ? ORDER BY m.ts DESC LIMIT 1`, chat))
	if err == sql.ErrNoRows {
		return Message{}, ErrNotFound
	}
	return m, err
}

// Mine returns up to limit of my messages in chat sent after since (Unix
// ms), sent and not deleted for everyone yet, newest first.
func (s *Store) Mine(ctx context.Context, chat string, since int64, limit int) ([]Message, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT `+messageColumns+` FROM cc_messages m
		 LEFT JOIN cc_media d ON d.chat_jid = m.chat_jid AND d.id = m.id
		 WHERE m.chat_jid = ? AND m.from_me = 1 AND m.ts > ? AND m.kind != ?
		 AND m.status NOT IN (?, ?) ORDER BY m.ts DESC LIMIT ?`,
		chat, since, KindRevoked, StatusSending, StatusFailed, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Message
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// DeleteChat deletes the chat's messages up to upTo (Unix ms; 0 = all) and,
// when none is left, the chat itself. It returns the messages whose media
// the vault must delete.
func (s *Store) DeleteChat(ctx context.Context, chat string, upTo int64) ([]string, error) {
	return s.deleteRange(ctx, chat, upTo, false)
}

// ClearChat deletes the chat's messages up to upTo (0 = all) and keeps the
// chat in the list, empty, as WhatsApp does.
func (s *Store) ClearChat(ctx context.Context, chat string, upTo int64) ([]string, error) {
	return s.deleteRange(ctx, chat, upTo, true)
}

func (s *Store) deleteRange(ctx context.Context, chat string, upTo int64, keep bool) ([]string, error) {
	if upTo <= 0 {
		upTo = 1<<63 - 1
	}
	var withMedia []string
	err := s.change(ctx, func(tx *sql.Tx) error {
		var err error
		withMedia, err = mediaIDs(ctx, tx,
			`SELECT d.id FROM cc_media d JOIN cc_messages m ON m.chat_jid = d.chat_jid AND m.id = d.id
			 WHERE d.chat_jid = ? AND m.ts <= ?`, chat, upTo)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx,
			`DELETE FROM cc_media WHERE chat_jid = ? AND id IN
			 (SELECT id FROM cc_messages WHERE chat_jid = ? AND ts <= ?)`, chat, chat, upTo); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx,
			`DELETE FROM cc_messages WHERE chat_jid = ? AND ts <= ?`, chat, upTo); err != nil {
			return err
		}
		return refreshChat(ctx, tx, chat, keep)
	})
	return withMedia, err
}

// DeleteMessage deletes one message ("apagar para mim") and reports whether
// it had media for the vault to delete. A missing message is not an error.
func (s *Store) DeleteMessage(ctx context.Context, chat, id string) (bool, error) {
	var hadMedia bool
	err := s.change(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `DELETE FROM cc_media WHERE chat_jid = ? AND id = ?`, chat, id)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		hadMedia = n > 0
		if _, err := tx.ExecContext(ctx,
			`DELETE FROM cc_messages WHERE chat_jid = ? AND id = ?`, chat, id); err != nil {
			return err
		}
		return refreshChat(ctx, tx, chat, true)
	})
	return hadMedia, err
}

// Revoke erases the content of a message deleted for everyone and keeps it
// as KindRevoked. It returns the message as it is now and whether it had
// media for the vault to delete; ErrNotFound when it is not stored.
func (s *Store) Revoke(ctx context.Context, chat, id string) (Message, bool, error) {
	var hadMedia bool
	err := s.change(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx,
			`UPDATE cc_messages SET kind = ?, text = '', forwarded = 0 WHERE chat_jid = ? AND id = ?`,
			KindRevoked, chat, id)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrNotFound
		}
		res, err = tx.ExecContext(ctx, `DELETE FROM cc_media WHERE chat_jid = ? AND id = ?`, chat, id)
		if err != nil {
			return err
		}
		n, _ := res.RowsAffected()
		hadMedia = n > 0
		return refreshChat(ctx, tx, chat, true)
	})
	if err != nil {
		return Message{}, false, err
	}
	m, err := s.Message(ctx, chat, id)
	return m, hadMedia, err
}

// ChatOf returns the chat holding message id, for updates that name the
// contact by its other address (phone number or LID). "" when none.
func (s *Store) ChatOf(ctx context.Context, id string, candidates ...string) (string, error) {
	for _, c := range candidates {
		var n int
		if err := s.db.QueryRowContext(ctx,
			`SELECT COUNT(*) FROM cc_messages WHERE chat_jid = ? AND id = ?`, c, id).Scan(&n); err != nil {
			return "", err
		}
		if n > 0 {
			return c, nil
		}
	}
	return "", nil
}

// AddPending queues a deletion to send to WhatsApp.
func (s *Store) AddPending(ctx context.Context, p Pending) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO cc_pending_sync (kind, chat_jid, id, from_me, sender, ts) VALUES (?, ?, ?, ?, ?, ?)`,
		p.Kind, p.Chat, p.ID, p.FromMe, p.Sender, p.TS)
	return err
}

// PendingList returns the queued deletions, oldest first.
func (s *Store) PendingList(ctx context.Context) ([]Pending, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT seq, kind, chat_jid, id, from_me, sender, ts FROM cc_pending_sync ORDER BY seq`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Pending
	for rows.Next() {
		var p Pending
		if err := rows.Scan(&p.Seq, &p.Kind, &p.Chat, &p.ID, &p.FromMe, &p.Sender, &p.TS); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// DonePending removes a deletion WhatsApp accepted.
func (s *Store) DonePending(ctx context.Context, seq int64) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM cc_pending_sync WHERE seq = ?`, seq)
	return err
}

// change runs a deletion in one transaction and then leaves no trace of the
// deleted content: the connection zeroes freed pages
// (secure_delete), the search index is merged so the old terms go, and the
// journal is emptied.
func (s *Store) change(ctx context.Context, fn func(*sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	return s.compact(ctx)
}

func (s *Store) compact(ctx context.Context) error {
	if _, err := s.db.ExecContext(ctx,
		`INSERT INTO cc_messages_fts(cc_messages_fts) VALUES ('optimize')`); err != nil {
		return err
	}
	// Busy readers only delay the checkpoint; it is not an error.
	_, err := s.db.ExecContext(ctx, `PRAGMA wal_checkpoint(TRUNCATE)`)
	return err
}

// refreshChat makes the chat list follow the newest message left. Without
// messages the chat goes away, or stays empty when keep is set.
func refreshChat(ctx context.Context, tx *sql.Tx, chat string, keep bool) error {
	m, err := scanMessage(tx.QueryRowContext(ctx,
		`SELECT `+messageColumns+` FROM cc_messages m
		 LEFT JOIN cc_media d ON d.chat_jid = m.chat_jid AND d.id = m.id
		 WHERE m.chat_jid = ? ORDER BY m.ts DESC LIMIT 1`, chat))
	switch {
	case err == nil:
		_, err = tx.ExecContext(ctx,
			`UPDATE cc_chats SET last_text = ?, last_ts = ? WHERE jid = ?`, m.Preview(), m.Timestamp, chat)
		return err
	case err != sql.ErrNoRows:
		return err
	case keep:
		_, err = tx.ExecContext(ctx, `UPDATE cc_chats SET last_text = '' WHERE jid = ?`, chat)
		return err
	default:
		_, err = tx.ExecContext(ctx, `DELETE FROM cc_chats WHERE jid = ?`, chat)
		return err
	}
}

func mediaIDs(ctx context.Context, tx *sql.Tx, query string, args ...any) ([]string, error) {
	rows, err := tx.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}
