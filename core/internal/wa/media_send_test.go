package wa

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/jpeg"
	"sync"
	"testing"

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

// fakeDeliverer stands for WhatsApp's media servers and send.
type fakeDeliverer struct {
	mu        sync.Mutex
	connected bool
	uploadErr error
	sendErr   error
	uploads   []whatsmeow.MediaType
	sent      []*waE2E.Message
	to        []types.JID
	syncErr   error
	patches   []appstate.PatchInfo
}

func (f *fakeDeliverer) IsConnected() bool { return f.connected }

func (f *fakeDeliverer) Upload(_ context.Context, data []byte, t whatsmeow.MediaType) (whatsmeow.UploadResponse, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.uploads = append(f.uploads, t)
	if f.uploadErr != nil {
		return whatsmeow.UploadResponse{}, f.uploadErr
	}
	return whatsmeow.UploadResponse{
		URL: "https://mmg.whatsapp.net/x", DirectPath: "/v/t62/x", MediaKey: bytes.Repeat([]byte{5}, 32),
		FileEncSHA256: []byte{1}, FileSHA256: []byte{2}, FileLength: uint64(len(data)),
	}, nil
}

func (f *fakeDeliverer) SendMessage(_ context.Context, to types.JID, m *waE2E.Message, _ ...whatsmeow.SendRequestExtra) (whatsmeow.SendResponse, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.sendErr != nil {
		return whatsmeow.SendResponse{}, f.sendErr
	}
	f.sent = append(f.sent, m)
	f.to = append(f.to, to)
	return whatsmeow.SendResponse{}, nil
}

func (f *fakeDeliverer) SendAppState(_ context.Context, p appstate.PatchInfo) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.syncErr != nil {
		return f.syncErr
	}
	f.patches = append(f.patches, p)
	return nil
}

func sendingSession(t *testing.T) (*Session, *fakeDeliverer, *[]map[string]any) {
	s, client, got := offlineSession(t)
	client.Store.ID = &me
	f := &fakeDeliverer{connected: true}
	s.deliverWith = func(*whatsmeow.Client) deliverer { return f }
	return s, f, got
}

func cameraPhoto(t *testing.T) []byte {
	t.Helper()
	img := image.NewNRGBA(image.Rect(0, 0, 40, 20))
	var b bytes.Buffer
	if err := jpeg.Encode(&b, img, nil); err != nil {
		t.Fatal(err)
	}
	// An EXIF block saying "turn right", as phone cameras write.
	exif := []byte("Exif\x00\x00MM\x00\x2a\x00\x00\x00\x08\x00\x01\x01\x12\x00\x03\x00\x00\x00\x01\x00\x06\x00\x00\x00\x00\x00\x00")
	seg := append([]byte{0xFF, 0xE1, 0, byte(2 + len(exif))}, exif...)
	src := b.Bytes()
	return append(append(append([]byte{}, src[:2]...), seg...), src[2:]...)
}

func TestSendPhotoUprightWithoutMetadata(t *testing.T) {
	s, f, got := sendingSession(t)
	m, err := s.SendMedia(alice.String(), MediaMeta{Kind: msgstore.KindImage, Caption: "olha"}, cameraPhoto(t))
	if err != nil {
		t.Fatal(err)
	}
	if m.Status != msgstore.StatusSending || m.Kind != msgstore.KindImage || m.Media != msgstore.MediaDownloaded ||
		!m.Thumb || m.Text != "olha" || m.Mime != "image/jpeg" {
		t.Fatalf("returned = %+v", m)
	}
	s.sends.Wait()

	full, _ := s.media.Get(vault.Name(alice.String(), m.ID, PartFull))
	if bytes.Contains(full, []byte("Exif")) || imgprep.Orientation(full) != 1 {
		t.Fatal("the photo kept its EXIF")
	}
	if cfg, _ := jpeg.DecodeConfig(bytes.NewReader(full)); cfg.Width != 20 || cfg.Height != 40 {
		t.Fatalf("photo not turned upright: %dx%d", cfg.Width, cfg.Height)
	}
	if len(f.uploads) != 1 || f.uploads[0] != whatsmeow.MediaImage || len(f.sent) != 1 {
		t.Fatalf("uploads %v, sent %d", f.uploads, len(f.sent))
	}
	img := f.sent[0].GetImageMessage()
	if img.GetDirectPath() != "/v/t62/x" || img.GetCaption() != "olha" || len(img.GetJPEGThumbnail()) == 0 ||
		img.GetMimetype() != "image/jpeg" || img.GetContextInfo() != nil {
		t.Fatalf("sent = %v", img)
	}
	st := eventsOf(*got, EventMessageStatus)
	if len(st) != 1 || st[0]["status"] != msgstore.StatusSent {
		t.Fatalf("status = %v", st)
	}
	// The upload is kept (without the thumbnail) to forward later.
	rec, _ := s.msgs.Media(t.Context(), alice.String(), m.ID)
	var stored waE2E.ImageMessage
	proto.Unmarshal(rec.Proto, &stored)
	if stored.GetDirectPath() != "/v/t62/x" || len(stored.GetJPEGThumbnail()) != 0 {
		t.Fatalf("stored = %v", &stored)
	}
}

func TestSendVoiceVideoAndDocument(t *testing.T) {
	s, f, _ := sendingSession(t)
	voice, _ := s.SendMedia(alice.String(), MediaMeta{Kind: msgstore.KindAudio, Seconds: 3, PTT: true, Caption: "x"}, []byte("OggS..."))
	s.sends.Wait()
	video, _ := s.SendMedia(alice.String(), MediaMeta{Kind: msgstore.KindVideo, Seconds: 4, Caption: "veja", Thumb: []byte{0xFF, 0xD8, 1}}, []byte("mp4"))
	s.sends.Wait()
	doc, _ := s.SendMedia(alice.String(), MediaMeta{Kind: msgstore.KindDocument, FileName: "contrato.pdf", Mime: "application/pdf"}, []byte("%PDF"))
	s.sends.Wait()

	if voice.Text != "" || !voice.PTT || voice.Seconds != 3 || voice.Mime != "audio/ogg; codecs=opus" || voice.Thumb {
		t.Fatalf("voice = %+v", voice)
	}
	if !video.Thumb || video.Mime != "video/mp4" {
		t.Fatalf("video = %+v", video)
	}
	if doc.FileName != "contrato.pdf" || doc.Size != 4 {
		t.Fatalf("doc = %+v", doc)
	}
	if got := f.uploads; len(got) != 3 || got[0] != whatsmeow.MediaAudio || got[1] != whatsmeow.MediaVideo ||
		got[2] != whatsmeow.MediaDocument {
		t.Fatalf("uploads = %v", got)
	}
	a := f.sent[0].GetAudioMessage()
	if !a.GetPTT() || a.GetSeconds() != 3 || a.GetMimetype() != "audio/ogg; codecs=opus" {
		t.Fatalf("audio = %v", a)
	}
	v := f.sent[1].GetVideoMessage()
	if v.GetSeconds() != 4 || v.GetCaption() != "veja" || !bytes.Equal(v.GetJPEGThumbnail(), []byte{0xFF, 0xD8, 1}) {
		t.Fatalf("video = %v", v)
	}
	d := f.sent[2].GetDocumentMessage()
	if d.GetFileName() != "contrato.pdf" || d.GetMimetype() != "application/pdf" || d.GetTitle() != "contrato.pdf" {
		t.Fatalf("document = %v", d)
	}
}

func TestSendMediaRefusesBadInput(t *testing.T) {
	s, _, _ := sendingSession(t)
	cases := map[string]struct {
		meta MediaMeta
		data []byte
		code string
	}{
		"kind":      {MediaMeta{Kind: "sticker"}, []byte{1}, bridge.CodeInvalidArgument},
		"empty":     {MediaMeta{Kind: msgstore.KindDocument}, nil, bridge.CodeInvalidArgument},
		"too big":   {MediaMeta{Kind: msgstore.KindAudio}, make([]byte, 16<<20+1), CodeTooBig},
		"not photo": {MediaMeta{Kind: msgstore.KindImage}, []byte("%PDF"), bridge.CodeInvalidArgument},
	}
	for name, c := range cases {
		if _, err := s.SendMedia(alice.String(), c.meta, c.data); errCode(err) != c.code {
			t.Errorf("%s: err = %v, want %s", name, err, c.code)
		}
	}
	if _, err := s.SendMedia("status@broadcast", MediaMeta{Kind: msgstore.KindDocument}, []byte{1}); errCode(err) != bridge.CodeInvalidArgument {
		t.Errorf("broadcast: %v", err)
	}
}

func TestMediaOfflineFailsAndRetryUploadsOnce(t *testing.T) {
	s, f, got := sendingSession(t)
	f.connected = false
	m, _ := s.SendMedia(alice.String(), MediaMeta{Kind: msgstore.KindDocument, FileName: "a.txt"}, []byte("oi"))
	s.sends.Wait()
	if st := eventsOf(*got, EventMessageStatus); st[len(st)-1]["status"] != msgstore.StatusFailed {
		t.Fatalf("offline: %v", st)
	}

	// Online, the upload works but the send fails: a retry reuses it.
	f.connected, f.sendErr = true, errors.New("server said no")
	if _, err := s.Retry(alice.String(), m.ID); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	f.sendErr = nil
	if _, err := s.Retry(alice.String(), m.ID); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if len(f.uploads) != 1 || len(f.sent) != 1 {
		t.Fatalf("uploads %d, sent %d", len(f.uploads), len(f.sent))
	}
	if st := eventsOf(*got, EventMessageStatus); st[len(st)-1]["status"] != msgstore.StatusSent {
		t.Fatalf("after retry: %v", st)
	}
	// A received media cannot be "resent".
	evt := message(alice, photo(true))
	evt.Info.ID = "R1"
	s.onMessage(s.client, evt)
	if _, err := s.Retry(alice.String(), "R1"); errCode(err) != bridge.CodeInvalidArgument {
		t.Fatalf("retry of a received media: %v", err)
	}
}

var bob = types.NewJID("5511900000002", types.DefaultUserServer)

func TestForwardTextWithTheMark(t *testing.T) {
	s, f, got := sendingSession(t)
	evt := message(alice, &waE2E.Message{Conversation: proto.String("bom dia")})
	evt.Info.ID = "T1"
	s.onMessage(s.client, evt)
	m, err := s.Forward(alice.String(), "T1", bob.String())
	if err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if !m.Forwarded || m.ChatJID != bob.String() || m.Text != "bom dia" || m.Status != msgstore.StatusSending {
		t.Fatalf("copy = %+v", m)
	}
	x := f.sent[0].GetExtendedTextMessage()
	if x.GetText() != "bom dia" || !x.GetContextInfo().GetIsForwarded() || f.to[0] != bob {
		t.Fatalf("sent = %v to %v", f.sent[0], f.to)
	}
	page, _ := s.ListMessages(bob.String(), 0, 10)
	if len(page) != 1 || !page[0].Forwarded {
		t.Fatalf("stored = %+v", page)
	}
	if st := eventsOf(*got, EventMessageStatus); st[len(st)-1]["status"] != msgstore.StatusSent {
		t.Fatalf("status = %v", st)
	}
}

func TestForwardMediaWithoutDownloading(t *testing.T) {
	s, f, _ := sendingSession(t)
	evt := message(alice, photo(true))
	evt.Info.ID = "P1"
	s.onMessage(s.client, evt)
	m, err := s.Forward(alice.String(), "P1", bob.String())
	if err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if len(f.uploads) != 0 {
		t.Fatalf("uploaded %v: should reuse the stored data", f.uploads)
	}
	img := f.sent[0].GetImageMessage()
	if img.GetDirectPath() != "/v/t62/fake" || !img.GetContextInfo().GetIsForwarded() ||
		!bytes.Equal(img.GetJPEGThumbnail(), thumb) || img.GetCaption() != "olha" {
		t.Fatalf("sent = %v", img)
	}
	if m.Media != msgstore.MediaThumb || !m.Thumb || m.Text != "olha" {
		t.Fatalf("copy = %+v", m)
	}
}

func TestForwardMediaInTheVaultUploadsAgain(t *testing.T) {
	s, f, _ := sendingSession(t)
	doc, _ := s.SendMedia(alice.String(), MediaMeta{Kind: msgstore.KindDocument, FileName: "a.pdf", Mime: "application/pdf"}, []byte("%PDF"))
	s.sends.Wait()
	copy, err := s.Forward(alice.String(), doc.ID, bob.String())
	if err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if len(f.uploads) != 2 || copy.Media != msgstore.MediaDownloaded || copy.FileName != "a.pdf" {
		t.Fatalf("uploads %v, copy %+v", f.uploads, copy)
	}
	d := f.sent[1].GetDocumentMessage()
	if d.GetFileName() != "a.pdf" || !d.GetContextInfo().GetIsForwarded() {
		t.Fatalf("sent = %v", d)
	}
	if data, _ := s.Media(bob.String(), copy.ID, PartFull); string(data) != "%PDF" {
		t.Fatal("the copy is not in the vault")
	}
}

func TestForwardRefusals(t *testing.T) {
	s, _, _ := sendingSession(t)
	sticker := message(alice, &waE2E.Message{StickerMessage: &waE2E.StickerMessage{}})
	sticker.Info.ID = "S1"
	s.onMessage(s.client, sticker)
	for name, c := range map[string][3]string{
		"unknown":  {alice.String(), "nope", bob.String()},
		"sticker":  {alice.String(), "S1", bob.String()},
		"bad chat": {alice.String(), "S1", "status@broadcast"},
	} {
		if _, err := s.Forward(c[0], c[1], c[2]); errCode(err) != bridge.CodeInvalidArgument {
			t.Errorf("%s: %v", name, err)
		}
	}
}
