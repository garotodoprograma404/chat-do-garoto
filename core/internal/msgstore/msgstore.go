// Package msgstore keeps the WhatsApp chats and messages the app shows, in
// our own tables (cc_*) of the same database as the whatsmeow session
package msgstore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

// Message kinds. Media keep their download data in cc_media.
const (
	KindText     = "text"
	KindImage    = "image"
	KindAudio    = "audio"
	KindVideo    = "video"
	KindDocument = "document"
	KindSticker  = "sticker"
	KindOther    = "other"
)

// Delivery status of my messages. Received messages and those
// from the history have no status ("").
const (
	StatusSending   = "sending"
	StatusSent      = "sent"
	StatusDelivered = "delivered"
	StatusRead      = "read"
	StatusFailed    = "failed"
)

// ErrNotFound is returned when a message is not stored.
var ErrNotFound = errors.New("message not found")

// Message is one WhatsApp message as the app sees it.
type Message struct {
	ChatJID    string `json:"chat"`
	ID         string `json:"id"`
	FromMe     bool   `json:"from_me"`
	SenderJID  string `json:"sender"`
	SenderName string `json:"sender_name"`
	Kind       string `json:"kind"`
	Text       string `json:"text"`
	Timestamp  int64  `json:"ts"` // Unix milliseconds
	Status     string `json:"status"`
	// Media state of a photo: "thumb", "remote", "downloaded",
	// "failed" or "expired"; "" for messages without stored media.
	Media string `json:"media"`
	// Thumb reports whether a thumbnail is in the vault.
	Thumb bool `json:"thumb"`
	// Media details: the document's name, the type, the size in
	// bytes, the length of audio and video, and whether an audio is a voice
	// message.
	FileName string `json:"file_name"`
	Mime     string `json:"mime"`
	Size     int64  `json:"size"`
	Seconds  int    `json:"seconds"`
	PTT      bool   `json:"ptt"`
	// Forwarded marks a forwarded message, received or sent.
	Forwarded bool `json:"forwarded"`
}

// Chat is one conversation in the chat list.
type Chat struct {
	JID      string `json:"jid"`
	Name     string `json:"name"`
	LastText string `json:"last_text"`
	LastTS   int64  `json:"last_ts"`
	// LastFromMe tells whether the newest message is mine, for the chats
	// waiting for a reply. A chat left without messages
	// counts as mine: there is nothing to reply to.
	LastFromMe bool `json:"last_from_me"`
}

// Preview is how a message shows up in the chat list.
func (m Message) Preview() string {
	switch m.Kind {
	case KindText:
		return m.Text
	case KindImage:
		return "[imagem]"
	case KindAudio:
		return "[áudio]"
	case KindVideo:
		return "[vídeo]"
	case KindDocument:
		return "[documento]"
	case KindSticker:
		return "[figurinha]"
	case KindRevoked:
		if m.FromMe {
			return "Você apagou esta mensagem"
		}
		return "Mensagem apagada"
	default:
		return "[outro]"
	}
}

// SearchSchemaVersion is the migration that adds the message search index
// ; the plain-to-encrypted conversion drops it to rebuild it.
const SearchSchemaVersion = 5

// Store reads and writes chats and messages.
type Store struct{ db *sql.DB }

var migrations = []string{
	// v1
	`CREATE TABLE cc_chats (
		jid       TEXT PRIMARY KEY,
		name      TEXT NOT NULL DEFAULT '',
		last_text TEXT NOT NULL DEFAULT '',
		last_ts   INTEGER NOT NULL DEFAULT 0
	);
	CREATE INDEX cc_chats_last_ts ON cc_chats(last_ts);
	CREATE TABLE cc_messages (
		chat_jid    TEXT NOT NULL,
		id          TEXT NOT NULL,
		from_me     INTEGER NOT NULL,
		sender_jid  TEXT NOT NULL DEFAULT '',
		sender_name TEXT NOT NULL DEFAULT '',
		kind        TEXT NOT NULL,
		text        TEXT NOT NULL DEFAULT '',
		ts          INTEGER NOT NULL,
		PRIMARY KEY (chat_jid, id)
	);
	CREATE INDEX cc_messages_chat_ts ON cc_messages(chat_jid, ts);`,
	// v2: delivery status of my messages
	`ALTER TABLE cc_messages ADD COLUMN status TEXT NOT NULL DEFAULT '';`,
	// v3: connection log, times and event kinds only
	`CREATE TABLE cc_connection_log (
		ts     INTEGER NOT NULL,
		kind   TEXT NOT NULL,
		source TEXT NOT NULL DEFAULT ''
	);
	CREATE INDEX cc_connection_log_ts ON cc_connection_log(ts);`,
	// v4: settings (the vault identity) and photos to download
	`CREATE TABLE cc_settings (
		name  TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);
	CREATE TABLE cc_media (
		chat_jid TEXT NOT NULL,
		id       TEXT NOT NULL,
		kind     TEXT NOT NULL,
		state    TEXT NOT NULL,
		thumb    INTEGER NOT NULL DEFAULT 0,
		proto    BLOB NOT NULL,
		PRIMARY KEY (chat_jid, id)
	);`,
	// v5: full-text search over message texts, without accents
	// (FTS4: built into the driver; FTS5 would need a build tag). External
	// content: the index points at cc_messages rows by rowid (never VACUUM
	// wa.db without rebuilding it). FTS4 reads the old text to unindex it,
	// so deletes and updates unindex BEFORE the row changes.
	`CREATE VIRTUAL TABLE cc_messages_fts USING fts4(
		content="cc_messages", text, tokenize=unicode61 "remove_diacritics=2"
	);
	CREATE TRIGGER cc_messages_fts_bd BEFORE DELETE ON cc_messages BEGIN
		DELETE FROM cc_messages_fts WHERE docid = old.rowid;
	END;
	CREATE TRIGGER cc_messages_fts_bu BEFORE UPDATE OF text ON cc_messages BEGIN
		DELETE FROM cc_messages_fts WHERE docid = old.rowid;
	END;
	CREATE TRIGGER cc_messages_fts_ai AFTER INSERT ON cc_messages BEGIN
		INSERT INTO cc_messages_fts(docid, text) VALUES (new.rowid, new.text);
	END;
	CREATE TRIGGER cc_messages_fts_au AFTER UPDATE OF text ON cc_messages BEGIN
		INSERT INTO cc_messages_fts(docid, text) VALUES (new.rowid, new.text);
	END;
	INSERT INTO cc_messages_fts(cc_messages_fts) VALUES ('rebuild');`,
	// v6: media details and the forwarded mark
	`ALTER TABLE cc_media ADD COLUMN file_name TEXT NOT NULL DEFAULT '';
	ALTER TABLE cc_media ADD COLUMN mime TEXT NOT NULL DEFAULT '';
	ALTER TABLE cc_media ADD COLUMN size INTEGER NOT NULL DEFAULT 0;
	ALTER TABLE cc_media ADD COLUMN seconds INTEGER NOT NULL DEFAULT 0;
	ALTER TABLE cc_media ADD COLUMN ptt INTEGER NOT NULL DEFAULT 0;
	ALTER TABLE cc_messages ADD COLUMN forwarded INTEGER NOT NULL DEFAULT 0;`,
	// v7: deletions still to send to WhatsApp, identifiers only
	`CREATE TABLE cc_pending_sync (
		seq      INTEGER PRIMARY KEY AUTOINCREMENT,
		kind     TEXT NOT NULL,
		chat_jid TEXT NOT NULL,
		id       TEXT NOT NULL DEFAULT '',
		from_me  INTEGER NOT NULL DEFAULT 0,
		sender   TEXT NOT NULL DEFAULT '',
		ts       INTEGER NOT NULL DEFAULT 0
	);`,
}

// Open prepares the tables in db, applying pending migrations.
func Open(ctx context.Context, db *sql.DB) (*Store, error) {
	if _, err := db.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS cc_schema (version INTEGER NOT NULL)`); err != nil {
		return nil, err
	}
	var version int
	if err := db.QueryRowContext(ctx, `SELECT COALESCE(MAX(version), 0) FROM cc_schema`).Scan(&version); err != nil {
		return nil, err
	}
	for v := version; v < len(migrations); v++ {
		tx, err := db.BeginTx(ctx, nil)
		if err != nil {
			return nil, err
		}
		if _, err := tx.ExecContext(ctx, migrations[v]); err != nil {
			tx.Rollback()
			return nil, fmt.Errorf("msgstore migration %d: %w", v+1, err)
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO cc_schema (version) VALUES (?)`, v+1); err != nil {
			tx.Rollback()
			return nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, err
		}
	}
	// The search index is dropped when a plain database is encrypted
	// (sqlcipher_export skips virtual tables): build it again here.
	var fts int
	if err := db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM sqlite_master WHERE name = 'cc_messages_fts'`).Scan(&fts); err != nil {
		return nil, err
	}
	if fts == 0 {
		if _, err := db.ExecContext(ctx, migrations[SearchSchemaVersion-1]); err != nil {
			return nil, fmt.Errorf("msgstore search index: %w", err)
		}
	}
	return &Store{db: db}, nil
}

// Save stores msgs in one transaction and returns the ones that were new
// (a message already stored is ignored). The chat list follows the newest
// message of each chat.
func (s *Store) Save(ctx context.Context, msgs []Message) ([]Message, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var added []Message
	for _, m := range msgs {
		res, err := tx.ExecContext(ctx,
			`INSERT OR IGNORE INTO cc_messages (chat_jid, id, from_me, sender_jid, sender_name, kind, text, ts, status, forwarded)
			 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
			m.ChatJID, m.ID, m.FromMe, m.SenderJID, m.SenderName, m.Kind, m.Text, m.Timestamp, m.Status, m.Forwarded)
		if err != nil {
			return nil, err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			continue
		}
		added = append(added, m)
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO cc_chats (jid, last_text, last_ts) VALUES (?, ?, ?)
			 ON CONFLICT(jid) DO UPDATE SET last_text = excluded.last_text, last_ts = excluded.last_ts
			 WHERE excluded.last_ts >= cc_chats.last_ts`,
			m.ChatJID, m.Preview(), m.Timestamp); err != nil {
			return nil, err
		}
	}
	return added, tx.Commit()
}

// SetChatName records the display name of a chat. Empty names are ignored.
func (s *Store) SetChatName(ctx context.Context, jid, name string) error {
	if name == "" {
		return nil
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO cc_chats (jid, name) VALUES (?, ?)
		 ON CONFLICT(jid) DO UPDATE SET name = excluded.name`, jid, name)
	return err
}

// HasChat reports whether a chat with that JID is stored with messages.
func (s *Store) HasChat(ctx context.Context, jid string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM cc_chats WHERE jid = ? AND last_ts > 0`, jid).Scan(&n)
	return n > 0, err
}

// ChatName returns the stored display name of a chat, or "".
func (s *Store) ChatName(ctx context.Context, jid string) (string, error) {
	var name string
	err := s.db.QueryRowContext(ctx, `SELECT name FROM cc_chats WHERE jid = ?`, jid).Scan(&name)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return name, err
}

// ListChats returns up to limit chats with at least one message, newest
// first.
func (s *Store) ListChats(ctx context.Context, limit int) ([]Chat, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT c.jid, c.name, c.last_text, c.last_ts,
		        COALESCE((SELECT m.from_me FROM cc_messages m WHERE m.chat_jid = c.jid
		                  ORDER BY m.ts DESC, m.rowid DESC LIMIT 1), 1)
		 FROM cc_chats c WHERE c.last_ts > 0
		 ORDER BY c.last_ts DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	chats := []Chat{}
	for rows.Next() {
		var c Chat
		if err := rows.Scan(&c.JID, &c.Name, &c.LastText, &c.LastTS, &c.LastFromMe); err != nil {
			return nil, err
		}
		chats = append(chats, c)
	}
	return chats, rows.Err()
}

// ListMessages returns up to limit messages of a chat older than beforeTS
// (0 = newest), oldest first.
func (s *Store) ListMessages(ctx context.Context, chatJID string, beforeTS int64, limit int) ([]Message, error) {
	if beforeTS <= 0 {
		beforeTS = 1<<63 - 1
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT `+messageColumns+` FROM cc_messages m
		 LEFT JOIN cc_media d ON d.chat_jid = m.chat_jid AND d.id = m.id
		 WHERE m.chat_jid = ? AND m.ts < ? ORDER BY m.ts DESC LIMIT ?`, chatJID, beforeTS, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	msgs := []Message{}
	for rows.Next() {
		m, err := scanMessage(rows)
		if err != nil {
			return nil, err
		}
		msgs = append(msgs, m)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	for i, j := 0, len(msgs)-1; i < j; i, j = i+1, j-1 {
		msgs[i], msgs[j] = msgs[j], msgs[i]
	}
	return msgs, nil
}

// Clear deletes every stored chat and message and the connection log
func (s *Store) Clear(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM cc_messages; DELETE FROM cc_chats; DELETE FROM cc_connection_log;
		 DELETE FROM cc_media; DELETE FROM cc_settings; DELETE FROM cc_pending_sync;`)
	return err
}

// ChatsWithoutName lists the chats that have messages but no display name.
func (s *Store) ChatsWithoutName(ctx context.Context) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT jid FROM cc_chats WHERE name = '' AND last_ts > 0`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var jids []string
	for rows.Next() {
		var j string
		if err := rows.Scan(&j); err != nil {
			return nil, err
		}
		jids = append(jids, j)
	}
	return jids, rows.Err()
}

const messageColumns = `m.chat_jid, m.id, m.from_me, m.sender_jid, m.sender_name, m.kind, m.text,
	m.ts, m.status, COALESCE(d.state, ''), COALESCE(d.thumb, 0), COALESCE(d.file_name, ''),
	COALESCE(d.mime, ''), COALESCE(d.size, 0), COALESCE(d.seconds, 0), COALESCE(d.ptt, 0), m.forwarded`

func scanMessage(row interface{ Scan(...any) error }) (Message, error) {
	var m Message
	err := row.Scan(&m.ChatJID, &m.ID, &m.FromMe, &m.SenderJID, &m.SenderName, &m.Kind, &m.Text,
		&m.Timestamp, &m.Status, &m.Media, &m.Thumb, &m.FileName, &m.Mime, &m.Size, &m.Seconds,
		&m.PTT, &m.Forwarded)
	return m, err
}

// Message returns one stored message, or ErrNotFound.
func (s *Store) Message(ctx context.Context, chatJID, id string) (Message, error) {
	m, err := scanMessage(s.db.QueryRowContext(ctx,
		`SELECT `+messageColumns+` FROM cc_messages m
		 LEFT JOIN cc_media d ON d.chat_jid = m.chat_jid AND d.id = m.id
		 WHERE m.chat_jid = ? AND m.id = ?`, chatJID, id))
	if err == sql.ErrNoRows {
		return Message{}, ErrNotFound
	}
	return m, err
}

// statusFrom lists, for each new status, the ones it may replace. A status
// only moves forward (a late "delivered" never undoes "read"); "failed" only
// ends a send, and a retry turns "failed" back into "sending". A receipt
// still counts after "failed": the message did arrive.
var statusFrom = map[string][]any{
	StatusSending:   {StatusFailed},
	StatusFailed:    {StatusSending},
	StatusSent:      {"", StatusSending, StatusFailed},
	StatusDelivered: {"", StatusSending, StatusFailed, StatusSent},
	StatusRead:      {"", StatusSending, StatusFailed, StatusSent, StatusDelivered},
}

// SetStatus moves my message id to status when the rules above allow it,
// and returns the chats where it changed (none when it did not). Messages
// are found by id alone, because WhatsApp may report a receipt under the
// contact's other address (phone number or LID).
func (s *Store) SetStatus(ctx context.Context, id, status string) ([]string, error) {
	from, ok := statusFrom[status]
	if !ok {
		return nil, fmt.Errorf("unknown status %q", status)
	}
	args := append([]any{status, id}, from...)
	rows, err := s.db.QueryContext(ctx,
		`UPDATE cc_messages SET status = ? WHERE id = ? AND from_me = 1
		 AND status IN (?`+strings.Repeat(", ?", len(from)-1)+`) RETURNING chat_jid`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var chats []string
	for rows.Next() {
		var c string
		if err := rows.Scan(&c); err != nil {
			return nil, err
		}
		chats = append(chats, c)
	}
	return chats, rows.Err()
}

// FailPending marks as failed the messages left "sending" when the app
// stopped.
func (s *Store) FailPending(ctx context.Context) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE cc_messages SET status = ? WHERE status = ?`, StatusFailed, StatusSending)
	return err
}
