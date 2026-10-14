package wa

import (
	"context"
	"errors"
	"strings"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/appstate"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/types"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/imgprep"
	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

// MediaMeta is what the app sends along with a media.
type MediaMeta struct {
	Kind     string `json:"kind"`
	Caption  string `json:"caption"`
	FileName string `json:"file_name"`
	Mime     string `json:"mime"`
	Seconds  int    `json:"seconds"`
	PTT      bool   `json:"ptt"`
	// Thumb is the preview of a video, made by the phone (base64 in JSON).
	Thumb []byte `json:"thumb"`
}

// CodeTooBig is the error for a media above the app's limit.
const CodeTooBig = "too_big"

// mediaLimits are the app's limits per kind.
var mediaLimits = map[string]int{
	msgstore.KindImage:    16 << 20,
	msgstore.KindAudio:    16 << 20,
	msgstore.KindVideo:    64 << 20,
	msgstore.KindDocument: 100 << 20,
}

// mediaSendTimeout bounds the upload and the send of one media.
const mediaSendTimeout = 5 * time.Minute

// deliverer is what sending needs from whatsmeow; tests replace it.
type deliverer interface {
	IsConnected() bool
	Upload(ctx context.Context, plaintext []byte, appInfo whatsmeow.MediaType) (whatsmeow.UploadResponse, error)
	SendMessage(ctx context.Context, to types.JID, message *waE2E.Message, extra ...whatsmeow.SendRequestExtra) (whatsmeow.SendResponse, error)
	// SendAppState sends deletions to my other devices.
	SendAppState(ctx context.Context, patch appstate.PatchInfo) error
}

// delivererOf returns how to reach WhatsApp through client.
func (s *Session) delivererOf(client *whatsmeow.Client) deliverer {
	if s.deliverWith != nil {
		return s.deliverWith(client)
	}
	return client
}

// SendMedia stores a media of mine as "sending", keeps it in the vault and
// returns it at once; the upload and the send run in the background and end
// as wa_message_status. Photos are re-encoded without
// metadata and turned upright first.
func (s *Session) SendMedia(chat string, meta MediaMeta, data []byte) (msgstore.Message, error) {
	limit, ok := mediaLimits[meta.Kind]
	if !ok {
		return msgstore.Message{}, invalidArgument("kind must be image, video, audio or document")
	}
	if len(data) == 0 {
		return msgstore.Message{}, invalidArgument("media is empty")
	}
	if len(data) > limit {
		return msgstore.Message{}, &bridge.Error{Code: CodeTooBig, Message: "media is too big"}
	}
	to, err := types.ParseJID(chat)
	if err != nil || to.User == "" || to.Server == types.BroadcastServer {
		return msgstore.Message{}, invalidArgument("invalid chat")
	}
	to = to.ToNonAD()

	s.mu.Lock()
	client, msgs, media := s.client, s.msgs, s.media
	s.mu.Unlock()
	if msgs == nil {
		return msgstore.Message{}, invalidState("call cc_wa_start first")
	}
	own := client.Store.ID
	if own == nil {
		return msgstore.Message{}, invalidState("not paired")
	}

	thumb := meta.Thumb
	switch meta.Kind {
	case msgstore.KindImage:
		photo, small, _, _, err := imgprep.Prepare(data)
		if err != nil {
			return msgstore.Message{}, invalidArgument("not a photo")
		}
		data, thumb, meta.Mime = photo, small, "image/jpeg"
	case msgstore.KindAudio:
		if meta.Mime == "" {
			meta.Mime = "audio/ogg; codecs=opus"
		}
		thumb = nil
	case msgstore.KindVideo:
		if meta.Mime == "" {
			meta.Mime = "video/mp4"
		}
	case msgstore.KindDocument:
		if meta.Mime == "" {
			meta.Mime = "application/octet-stream"
		}
		if strings.TrimSpace(meta.FileName) == "" {
			meta.FileName = "documento"
		}
	}
	caption := meta.Caption
	if meta.Kind == msgstore.KindAudio {
		caption = ""
	}

	ctx := context.Background()
	m := msgstore.Message{
		ChatJID:   to.String(),
		ID:        client.GenerateMessageID(),
		FromMe:    true,
		SenderJID: own.ToNonAD().String(),
		Kind:      meta.Kind,
		Text:      caption,
		Timestamp: time.Now().UnixMilli(),
		Status:    msgstore.StatusSending,
	}
	if _, err := msgs.Save(ctx, []msgstore.Message{m}); err != nil {
		return msgstore.Message{}, err
	}
	if err := media.Put(vault.Name(m.ChatJID, m.ID, PartFull), data); err != nil {
		return msgstore.Message{}, err
	}
	hasThumb := len(thumb) > 0 && media.Put(vault.Name(m.ChatJID, m.ID, PartThumb), thumb) == nil
	if err := msgs.SaveMedia(ctx, msgstore.MediaRecord{
		ChatJID: m.ChatJID, ID: m.ID, Kind: meta.Kind, State: msgstore.MediaDownloaded, Thumb: hasThumb,
		FileName: meta.FileName, Mime: meta.Mime, Size: int64(len(data)), Seconds: meta.Seconds, PTT: meta.PTT,
	}); err != nil {
		return msgstore.Message{}, err
	}
	fillMedia(ctx, msgs, &m)
	s.hub.Emit(EventMessage, m)
	s.startMediaDelivery(client, msgs, media, to, m)
	return m, nil
}

// startMediaDelivery uploads (when needed) and sends a media of mine in the
// background, without the session lock (core/DESENVOLVIMENTO.md).
func (s *Session) startMediaDelivery(client *whatsmeow.Client, msgs *msgstore.Store, media *vault.Vault, to types.JID, m msgstore.Message) {
	d := s.delivererOf(client)
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		status := msgstore.StatusFailed
		if d.IsConnected() {
			ctx, cancel := context.WithTimeout(context.Background(), mediaSendTimeout)
			msg, err := mediaMessage(ctx, d, msgs, media, m)
			if err == nil {
				_, err = d.SendMessage(ctx, to, msg, whatsmeow.SendRequestExtra{ID: m.ID})
			}
			cancel()
			if err == nil {
				status = msgstore.StatusSent
			}
		}
		s.setStatus(msgs, m.ID, status)
	}()
}

// mediaTypes says how whatsmeow encrypts each kind.
var mediaTypes = map[string]whatsmeow.MediaType{
	msgstore.KindImage:    whatsmeow.MediaImage,
	msgstore.KindVideo:    whatsmeow.MediaVideo,
	msgstore.KindAudio:    whatsmeow.MediaAudio,
	msgstore.KindDocument: whatsmeow.MediaDocument,
}

// mediaMessage builds the WhatsApp message of a media of mine. The upload
// happens once: its result is kept in cc_media, so a retry or a forward
// reuses it.
func mediaMessage(ctx context.Context, d deliverer, msgs *msgstore.Store, media *vault.Vault, m msgstore.Message) (*waE2E.Message, error) {
	rec, err := msgs.Media(ctx, m.ChatJID, m.ID)
	if err != nil {
		return nil, err
	}
	raw := rec.Proto
	if len(raw) == 0 {
		data, err := media.Get(vault.Name(m.ChatJID, m.ID, PartFull))
		if err != nil {
			return nil, err
		}
		up, err := d.Upload(ctx, data, mediaTypes[rec.Kind])
		clear(data)
		if err != nil {
			return nil, err
		}
		if raw, err = uploaded(rec, m.Text, up); err != nil {
			return nil, err
		}
		if err := msgs.SetMediaProto(ctx, m.ChatJID, m.ID, raw); err != nil {
			return nil, err
		}
	}
	var thumb []byte
	if rec.Thumb {
		thumb, _ = media.Get(vault.Name(m.ChatJID, m.ID, PartThumb))
	}
	return outgoing(rec.Kind, raw, thumb, m.Forwarded)
}

// uploaded builds the stored download data of a media of mine after its
// upload (no thumbnail: it lives in the vault).
func uploaded(rec msgstore.MediaRecord, caption string, up whatsmeow.UploadResponse) ([]byte, error) {
	var msg proto.Message
	switch rec.Kind {
	case msgstore.KindImage:
		msg = &waE2E.ImageMessage{
			URL: proto.String(up.URL), DirectPath: proto.String(up.DirectPath), MediaKey: up.MediaKey,
			FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: proto.Uint64(up.FileLength),
			Mimetype: proto.String(rec.Mime), Caption: optional(caption),
		}
	case msgstore.KindVideo:
		msg = &waE2E.VideoMessage{
			URL: proto.String(up.URL), DirectPath: proto.String(up.DirectPath), MediaKey: up.MediaKey,
			FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: proto.Uint64(up.FileLength),
			Mimetype: proto.String(rec.Mime), Caption: optional(caption), Seconds: proto.Uint32(uint32(rec.Seconds)),
		}
	case msgstore.KindAudio:
		msg = &waE2E.AudioMessage{
			URL: proto.String(up.URL), DirectPath: proto.String(up.DirectPath), MediaKey: up.MediaKey,
			FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: proto.Uint64(up.FileLength),
			Mimetype: proto.String(rec.Mime), Seconds: proto.Uint32(uint32(rec.Seconds)), PTT: proto.Bool(rec.PTT),
		}
	case msgstore.KindDocument:
		msg = &waE2E.DocumentMessage{
			URL: proto.String(up.URL), DirectPath: proto.String(up.DirectPath), MediaKey: up.MediaKey,
			FileEncSHA256: up.FileEncSHA256, FileSHA256: up.FileSHA256, FileLength: proto.Uint64(up.FileLength),
			Mimetype: proto.String(rec.Mime), FileName: proto.String(rec.FileName), Title: proto.String(rec.FileName),
			Caption: optional(caption),
		}
	default:
		return nil, errors.New("no media")
	}
	return proto.Marshal(msg)
}

func optional(s string) *string {
	if s == "" {
		return nil
	}
	return proto.String(s)
}

// outgoing turns stored download data back into a message to send, with the
// thumbnail and, for a forward, the mark.
func outgoing(kind string, raw, thumb []byte, forwarded bool) (*waE2E.Message, error) {
	var info *waE2E.ContextInfo
	if forwarded {
		info = &waE2E.ContextInfo{IsForwarded: proto.Bool(true), ForwardingScore: proto.Uint32(1)}
	}
	switch kind {
	case msgstore.KindImage:
		var img waE2E.ImageMessage
		if err := proto.Unmarshal(raw, &img); err != nil {
			return nil, err
		}
		img.JPEGThumbnail, img.ContextInfo = thumb, info
		return &waE2E.Message{ImageMessage: &img}, nil
	case msgstore.KindVideo:
		var v waE2E.VideoMessage
		if err := proto.Unmarshal(raw, &v); err != nil {
			return nil, err
		}
		v.JPEGThumbnail, v.ContextInfo = thumb, info
		return &waE2E.Message{VideoMessage: &v}, nil
	case msgstore.KindAudio:
		var a waE2E.AudioMessage
		if err := proto.Unmarshal(raw, &a); err != nil {
			return nil, err
		}
		a.ContextInfo = info
		return &waE2E.Message{AudioMessage: &a}, nil
	case msgstore.KindDocument:
		var d waE2E.DocumentMessage
		if err := proto.Unmarshal(raw, &d); err != nil {
			return nil, err
		}
		d.JPEGThumbnail, d.ContextInfo = thumb, info
		return &waE2E.Message{DocumentMessage: &d}, nil
	}
	return nil, errors.New("no media")
}
