package msgstore

import (
	"context"
	"database/sql"
)

// Media states.
const (
	MediaThumb      = "thumb"      // thumbnail stored, media not downloaded
	MediaRemote     = "remote"     // no thumbnail, media not downloaded
	MediaDownloaded = "downloaded" // the media is in the vault
	MediaFailed     = "failed"     // the last download failed; may retry
	MediaExpired    = "expired"    // WhatsApp no longer has the media
)

// MediaRecord is what is needed to download (or forward) a media later.
// Proto holds the WhatsApp media key: it only lives in the encrypted wa.db.
// It is empty for a media of mine until its upload finishes.
type MediaRecord struct {
	ChatJID  string
	ID       string
	Kind     string
	State    string
	Thumb    bool
	Proto    []byte
	FileName string
	Mime     string
	Size     int64
	Seconds  int
	PTT      bool
}

// SaveMedia records a media once; a record already stored is kept.
func (s *Store) SaveMedia(ctx context.Context, r MediaRecord) error {
	if r.Proto == nil {
		r.Proto = []byte{}
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT OR IGNORE INTO cc_media (chat_jid, id, kind, state, thumb, proto, file_name, mime, size, seconds, ptt)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		r.ChatJID, r.ID, r.Kind, r.State, r.Thumb, r.Proto, r.FileName, r.Mime, r.Size, r.Seconds, r.PTT)
	return err
}

// Media returns the record of a media, or ErrNotFound.
func (s *Store) Media(ctx context.Context, chatJID, id string) (MediaRecord, error) {
	r := MediaRecord{ChatJID: chatJID, ID: id}
	err := s.db.QueryRowContext(ctx,
		`SELECT kind, state, thumb, proto, file_name, mime, size, seconds, ptt
		 FROM cc_media WHERE chat_jid = ? AND id = ?`, chatJID, id).
		Scan(&r.Kind, &r.State, &r.Thumb, &r.Proto, &r.FileName, &r.Mime, &r.Size, &r.Seconds, &r.PTT)
	if err == sql.ErrNoRows {
		return MediaRecord{}, ErrNotFound
	}
	return r, err
}

// SetMediaProto keeps the download data of a media of mine once uploaded,
// so it can be forwarded without uploading again.
func (s *Store) SetMediaProto(ctx context.Context, chatJID, id string, raw []byte) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE cc_media SET proto = ? WHERE chat_jid = ? AND id = ?`, raw, chatJID, id)
	return err
}

// SetMediaState records the outcome of a download.
func (s *Store) SetMediaState(ctx context.Context, chatJID, id, state string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE cc_media SET state = ? WHERE chat_jid = ? AND id = ?`, state, chatJID, id)
	return err
}

// Setting returns a stored setting, or "" when missing.
func (s *Store) Setting(ctx context.Context, name string) (string, error) {
	var v string
	err := s.db.QueryRowContext(ctx, `SELECT value FROM cc_settings WHERE name = ?`, name).Scan(&v)
	if err == sql.ErrNoRows {
		return "", nil
	}
	return v, err
}

// SetSetting stores a setting.
func (s *Store) SetSetting(ctx context.Context, name, value string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO cc_settings (name, value) VALUES (?, ?)
		 ON CONFLICT(name) DO UPDATE SET value = excluded.value`, name, value)
	return err
}
