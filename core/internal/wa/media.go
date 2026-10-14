package wa

import (
	"context"
	"errors"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

// EventMedia reports the outcome of a media download.
// data: {"chat", "id", "state"}.
const EventMedia = "wa_media"

// Parts of a media in the vault: the thumbnail and the media itself.
const (
	PartThumb = "thumb"
	PartFull  = "full"
)

const (
	vaultIdentity   = "vault_identity"
	downloadTimeout = 2 * time.Minute
)

// openVault opens the media vault in dir, creating its identity on first
// use. The identity lives in wa.db.
func openVault(ctx context.Context, msgs *msgstore.Store, dir string) (*vault.Vault, error) {
	identity, err := msgs.Setting(ctx, vaultIdentity)
	if err != nil {
		return nil, err
	}
	if identity == "" {
		if identity, err = vault.NewIdentity(); err != nil {
			return nil, err
		}
		if err := msgs.SetSetting(ctx, vaultIdentity, identity); err != nil {
			return nil, err
		}
	}
	return vault.Open(dir, identity)
}

// mediaOf returns the media part of m: its kind, the thumbnail WhatsApp
// sent, the download data without the thumbnail, and the details shown in
// the conversation. ok is false for messages without
// a media to keep (text, stickers…).
func mediaOf(m *waE2E.Message) (rec msgstore.MediaRecord, thumb []byte, ok bool) {
	var rest proto.Message
	switch {
	case m.GetImageMessage() != nil:
		img := proto.Clone(m.GetImageMessage()).(*waE2E.ImageMessage)
		thumb, img.JPEGThumbnail = img.GetJPEGThumbnail(), nil
		rec = msgstore.MediaRecord{Kind: msgstore.KindImage, Mime: img.GetMimetype(), Size: int64(img.GetFileLength())}
		rest = img
	case m.GetVideoMessage() != nil:
		v := proto.Clone(m.GetVideoMessage()).(*waE2E.VideoMessage)
		thumb, v.JPEGThumbnail = v.GetJPEGThumbnail(), nil
		rec = msgstore.MediaRecord{Kind: msgstore.KindVideo, Mime: v.GetMimetype(), Size: int64(v.GetFileLength()),
			Seconds: int(v.GetSeconds())}
		rest = v
	case m.GetAudioMessage() != nil:
		a := m.GetAudioMessage()
		rec = msgstore.MediaRecord{Kind: msgstore.KindAudio, Mime: a.GetMimetype(), Size: int64(a.GetFileLength()),
			Seconds: int(a.GetSeconds()), PTT: a.GetPTT()}
		rest = a
	case m.GetDocumentMessage() != nil:
		d := proto.Clone(m.GetDocumentMessage()).(*waE2E.DocumentMessage)
		thumb, d.JPEGThumbnail = d.GetJPEGThumbnail(), nil
		rec = msgstore.MediaRecord{Kind: msgstore.KindDocument, Mime: d.GetMimetype(), Size: int64(d.GetFileLength()),
			FileName: d.GetFileName()}
		rest = d
	default:
		return msgstore.MediaRecord{}, nil, false
	}
	raw, err := proto.Marshal(rest)
	if err != nil {
		return msgstore.MediaRecord{}, nil, false
	}
	rec.Proto = raw
	return rec, thumb, true
}

// storeMedia keeps the thumbnail of a media message in the vault and what
// is needed to download it later. It
// fills the media fields of m.
func storeMedia(ctx context.Context, msgs *msgstore.Store, media *vault.Vault, m *msgstore.Message, msg *waE2E.Message) {
	rec, thumb, ok := mediaOf(msg)
	if !ok {
		return
	}
	rec.ChatJID, rec.ID = m.ChatJID, m.ID
	rec.Thumb = len(thumb) > 0 && media.Put(vault.Name(m.ChatJID, m.ID, PartThumb), thumb) == nil
	rec.State = msgstore.MediaRemote
	if rec.Thumb {
		rec.State = msgstore.MediaThumb
	}
	if err := msgs.SaveMedia(ctx, rec); err != nil {
		return
	}
	fillMedia(ctx, msgs, m)
}

// fillMedia copies the stored media details into m.
func fillMedia(ctx context.Context, msgs *msgstore.Store, m *msgstore.Message) {
	if stored, err := msgs.Message(ctx, m.ChatJID, m.ID); err == nil {
		m.Media, m.Thumb, m.FileName, m.Mime = stored.Media, stored.Thumb, stored.FileName, stored.Mime
		m.Size, m.Seconds, m.PTT = stored.Size, stored.Seconds, stored.PTT
	}
}

// downloadable rebuilds the download data stored for a media of kind.
func downloadable(kind string, raw []byte) (whatsmeow.DownloadableMessage, error) {
	var msg whatsmeow.DownloadableMessage
	switch kind {
	case msgstore.KindImage:
		msg = &waE2E.ImageMessage{}
	case msgstore.KindVideo:
		msg = &waE2E.VideoMessage{}
	case msgstore.KindAudio:
		msg = &waE2E.AudioMessage{}
	case msgstore.KindDocument:
		msg = &waE2E.DocumentMessage{}
	default:
		return nil, invalidArgument("no media in this message")
	}
	if err := proto.Unmarshal(raw, msg.(proto.Message)); err != nil {
		return nil, err
	}
	return msg, nil
}

// DownloadMedia downloads a media into the vault in the background; the
// outcome arrives as wa_media. Nothing is downloaded without this call
func (s *Session) DownloadMedia(chat, id string) error {
	s.mu.Lock()
	client, msgs, media := s.client, s.msgs, s.media
	s.mu.Unlock()
	if msgs == nil {
		return invalidState("call cc_wa_start first")
	}
	ctx := context.Background()
	rec, err := msgs.Media(ctx, chat, id)
	if errors.Is(err, msgstore.ErrNotFound) {
		return invalidArgument("no media in this message")
	}
	if err != nil {
		return err
	}
	if rec.State == msgstore.MediaDownloaded && media.Has(vault.Name(chat, id, PartFull)) ||
		rec.State == msgstore.MediaExpired {
		s.hub.Emit(EventMedia, map[string]any{"chat": chat, "id": id, "state": rec.State})
		return nil
	}
	msg, err := downloadable(rec.Kind, rec.Proto)
	if err != nil {
		return err
	}
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		state := downloadInto(client, media, chat, id, msg)
		if err := msgs.SetMediaState(context.Background(), chat, id, state); err != nil {
			s.hub.Emit(EventError, map[string]any{"code": ErrStoreFailed})
		}
		s.hub.Emit(EventMedia, map[string]any{"chat": chat, "id": id, "state": state})
	}()
	return nil
}

// downloadInto fetches a media from WhatsApp's media servers (through
// whatsmeow, which also checks and decrypts it) and keeps it in the vault.
func downloadInto(client *whatsmeow.Client, media *vault.Vault, chat, id string, msg whatsmeow.DownloadableMessage) string {
	if !client.IsConnected() {
		return msgstore.MediaFailed
	}
	ctx, cancel := context.WithTimeout(context.Background(), downloadTimeout)
	defer cancel()
	data, err := client.Download(ctx, msg)
	switch {
	case errors.Is(err, whatsmeow.ErrMediaDownloadFailedWith404),
		errors.Is(err, whatsmeow.ErrMediaDownloadFailedWith410):
		return msgstore.MediaExpired
	case err != nil:
		return msgstore.MediaFailed
	}
	defer clear(data)
	if media.Put(vault.Name(chat, id, PartFull), data) != nil {
		return msgstore.MediaFailed
	}
	return msgstore.MediaDownloaded
}

// Media returns a part of a stored media, decrypted in memory.
func (s *Session) Media(chat, id, part string) ([]byte, error) {
	if part != PartThumb && part != PartFull {
		return nil, invalidArgument("part must be thumb or full")
	}
	s.mu.Lock()
	media := s.media
	s.mu.Unlock()
	if media == nil {
		return nil, invalidState("call cc_wa_start first")
	}
	data, err := media.Get(vault.Name(chat, id, part))
	if errors.Is(err, vault.ErrNotFound) {
		return nil, invalidArgument("not in the vault")
	}
	return data, err
}
