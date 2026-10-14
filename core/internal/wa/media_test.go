package wa

import (
	"bytes"
	"testing"

	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waHistorySync"
	"go.mau.fi/whatsmeow/proto/waWeb"
	waevents "go.mau.fi/whatsmeow/types/events"
	"google.golang.org/protobuf/proto"

	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

var thumb = []byte{0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3}

func photo(withThumb bool) *waE2E.Message {
	img := &waE2E.ImageMessage{
		Caption:    proto.String("olha"),
		Mimetype:   proto.String("image/jpeg"),
		DirectPath: proto.String("/v/t62/fake"),
		MediaKey:   bytes.Repeat([]byte{7}, 32),
	}
	if withThumb {
		img.JPEGThumbnail = thumb
	}
	return &waE2E.Message{ImageMessage: img}
}

func TestLivePhotoKeepsItsThumbnailInTheVault(t *testing.T) {
	s, client, got := offlineSession(t)
	evt := message(alice, photo(true))
	evt.Info.ID = "P1"
	s.onMessage(client, evt)

	live := eventsOf(*got, EventMessage)
	if len(live) != 1 || live[0]["media"] != msgstore.MediaThumb || live[0]["thumb"] != true || live[0]["text"] != "olha" {
		t.Fatalf("wa_message = %v", live)
	}
	data, err := s.Media(alice.String(), "P1", PartThumb)
	if err != nil || !bytes.Equal(data, thumb) {
		t.Fatalf("thumb = %x, %v", data, err)
	}
	rec, _ := s.msgs.Media(t.Context(), alice.String(), "P1")
	var stored waE2E.ImageMessage
	proto.Unmarshal(rec.Proto, &stored)
	if len(stored.GetJPEGThumbnail()) != 0 || stored.GetDirectPath() != "/v/t62/fake" {
		t.Fatalf("stored download data = %v", &stored)
	}
	if _, err := s.Media(alice.String(), "P1", PartFull); errCode(err) != bridge.CodeInvalidArgument {
		t.Fatalf("full photo before download: %v", err)
	}
}

func TestPhotoWithoutThumbnailIsRemote(t *testing.T) {
	s, client, got := offlineSession(t)
	evt := message(alice, photo(false))
	evt.Info.ID = "P2"
	s.onMessage(client, evt)
	if live := eventsOf(*got, EventMessage); live[0]["media"] != msgstore.MediaRemote || live[0]["thumb"] != false {
		t.Fatalf("wa_message = %v", live)
	}
}

func TestHistoryPhotosAreRecorded(t *testing.T) {
	s, client, _ := offlineSession(t)
	hm := &waHistorySync.HistorySyncMsg{Message: &waWeb.WebMessageInfo{
		Key:              webMsg(alice, "H1", 100, "").Message.Key,
		MessageTimestamp: proto.Uint64(100),
		Message:          photo(true),
	}}
	s.onHistory(client, &waevents.HistorySync{Data: &waHistorySync.HistorySync{
		Conversations: []*waHistorySync.Conversation{{ID: proto.String(alice.String()), Messages: []*waHistorySync.HistorySyncMsg{hm}}},
	}})
	page, _ := s.ListMessages(alice.String(), 0, 10)
	if len(page) != 1 || page[0].Media != msgstore.MediaThumb || !page[0].Thumb {
		t.Fatalf("history page = %+v", page)
	}
}

func TestDownloadOfflineFailsAndExpiredIsNotRetried(t *testing.T) {
	s, client, got := offlineSession(t)
	evt := message(alice, photo(true))
	evt.Info.ID = "P3"
	s.onMessage(client, evt)

	if err := s.DownloadMedia(alice.String(), "nope"); errCode(err) != bridge.CodeInvalidArgument {
		t.Fatalf("unknown photo: %v", err)
	}
	if err := s.DownloadMedia(alice.String(), "P3"); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	media := eventsOf(*got, EventMedia)
	if len(media) != 1 || media[0]["state"] != msgstore.MediaFailed {
		t.Fatalf("wa_media = %v", media)
	}

	s.msgs.SetMediaState(t.Context(), alice.String(), "P3", msgstore.MediaExpired)
	if err := s.DownloadMedia(alice.String(), "P3"); err != nil {
		t.Fatal(err)
	}
	if media := eventsOf(*got, EventMedia); media[len(media)-1]["state"] != msgstore.MediaExpired {
		t.Fatalf("expired: %v", media)
	}
}

func TestDownloadedPhotoOpensWithoutDownloadingAgain(t *testing.T) {
	s, client, got := offlineSession(t)
	evt := message(alice, photo(true))
	evt.Info.ID = "P4"
	s.onMessage(client, evt)
	full := []byte{0xFF, 0xD8, 0xFF, 9, 9}
	s.media.Put(vault.Name(alice.String(), "P4", PartFull), full)
	s.msgs.SetMediaState(t.Context(), alice.String(), "P4", msgstore.MediaDownloaded)

	if err := s.DownloadMedia(alice.String(), "P4"); err != nil {
		t.Fatal(err)
	}
	if media := eventsOf(*got, EventMedia); len(media) != 1 || media[0]["state"] != msgstore.MediaDownloaded {
		t.Fatalf("wa_media = %v", media)
	}
	if data, _ := s.Media(alice.String(), "P4", PartFull); !bytes.Equal(data, full) {
		t.Fatal("full photo not read back")
	}
	if _, err := s.Media(alice.String(), "P4", "other"); errCode(err) != bridge.CodeInvalidArgument {
		t.Fatalf("bad part: %v", err)
	}
}

func TestUnlinkingClearsTheVault(t *testing.T) {
	s, client, _ := offlineSession(t)
	evt := message(alice, photo(true))
	evt.Info.ID = "P5"
	s.onMessage(client, evt)
	media, msgs := s.media, s.msgs
	s.handle(client, &waevents.LoggedOut{})
	if media.Has(vault.Name(alice.String(), "P5", PartThumb)) {
		t.Fatal("thumbnail survived unlinking")
	}
	if v, _ := msgs.Setting(t.Context(), vaultIdentity); v != "" {
		t.Fatal("vault identity survived unlinking")
	}
}

func TestAudioVideoAndDocumentsAreKeptLikePhotos(t *testing.T) {
	s, client, got := offlineSession(t)
	voice := message(alice, &waE2E.Message{AudioMessage: &waE2E.AudioMessage{
		Mimetype: proto.String("audio/ogg; codecs=opus"), Seconds: proto.Uint32(7), PTT: proto.Bool(true),
		FileLength: proto.Uint64(4000), DirectPath: proto.String("/v/a"), MediaKey: bytes.Repeat([]byte{1}, 32),
	}})
	voice.Info.ID = "A1"
	video := message(alice, &waE2E.Message{VideoMessage: &waE2E.VideoMessage{
		Caption: proto.String("veja"), Mimetype: proto.String("video/mp4"), Seconds: proto.Uint32(12),
		JPEGThumbnail: thumb, DirectPath: proto.String("/v/v"), MediaKey: bytes.Repeat([]byte{2}, 32),
	}})
	video.Info.ID = "V1"
	doc := message(alice, &waE2E.Message{DocumentMessage: &waE2E.DocumentMessage{
		FileName: proto.String("contrato.pdf"), Mimetype: proto.String("application/pdf"),
		FileLength: proto.Uint64(12345), JPEGThumbnail: thumb, DirectPath: proto.String("/v/d"),
		MediaKey:    bytes.Repeat([]byte{3}, 32),
		ContextInfo: &waE2E.ContextInfo{IsForwarded: proto.Bool(true)},
	}})
	doc.Info.ID = "D1"
	for _, evt := range []*waevents.Message{voice, video, doc} {
		s.onMessage(client, evt)
	}

	live := eventsOf(*got, EventMessage)
	if a := live[0]; a["kind"] != msgstore.KindAudio || a["media"] != msgstore.MediaRemote ||
		a["seconds"] != 7.0 || a["ptt"] != true || a["mime"] != "audio/ogg; codecs=opus" {
		t.Fatalf("voice = %v", a)
	}
	if v := live[1]; v["kind"] != msgstore.KindVideo || v["media"] != msgstore.MediaThumb || v["seconds"] != 12.0 ||
		v["text"] != "veja" {
		t.Fatalf("video = %v", v)
	}
	if d := live[2]; d["file_name"] != "contrato.pdf" || d["size"] != 12345.0 || d["forwarded"] != true ||
		d["media"] != msgstore.MediaThumb {
		t.Fatalf("document = %v", d)
	}
	if data, _ := s.Media(alice.String(), "V1", PartThumb); !bytes.Equal(data, thumb) {
		t.Fatal("video thumbnail not in the vault")
	}
	// Every kind downloads only when asked; offline it fails. One at a time:
	// the test listener is not safe for concurrent events.
	for _, id := range []string{"A1", "V1", "D1"} {
		if err := s.DownloadMedia(alice.String(), id); err != nil {
			t.Fatalf("download %s: %v", id, err)
		}
		s.sends.Wait()
	}
	for _, m := range eventsOf(*got, EventMedia) {
		if m["state"] != msgstore.MediaFailed {
			t.Fatalf("wa_media = %v", m)
		}
	}
	rec, _ := s.msgs.Media(t.Context(), alice.String(), "D1")
	var stored waE2E.DocumentMessage
	proto.Unmarshal(rec.Proto, &stored)
	if len(stored.GetJPEGThumbnail()) != 0 || stored.GetDirectPath() != "/v/d" {
		t.Fatalf("stored download data = %v", &stored)
	}
}

func TestTextAndStickersHaveNoMedia(t *testing.T) {
	s, client, _ := offlineSession(t)
	evt := message(alice, &waE2E.Message{ExtendedTextMessage: &waE2E.ExtendedTextMessage{
		Text: proto.String("encaminhado"), ContextInfo: &waE2E.ContextInfo{IsForwarded: proto.Bool(true)},
	}})
	evt.Info.ID = "T1"
	s.onMessage(client, evt)
	sticker := message(alice, &waE2E.Message{StickerMessage: &waE2E.StickerMessage{}})
	sticker.Info.ID = "S1"
	s.onMessage(client, sticker)
	page, _ := s.ListMessages(alice.String(), 0, 10)
	if page[0].Media != "" || !page[0].Forwarded || page[1].Media != "" {
		t.Fatalf("page = %+v", page)
	}
	if err := s.DownloadMedia(alice.String(), "S1"); errCode(err) != bridge.CodeInvalidArgument {
		t.Fatalf("sticker download: %v", err)
	}
}
