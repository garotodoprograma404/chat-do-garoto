package msgstore

import (
	"context"
	"database/sql"
	"path/filepath"
	"testing"
)

func TestMediaRecordsJoinTheirMessages(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{{ChatJID: "a@s", ID: "p1", Kind: KindImage, Text: "legenda", Timestamp: 10}, msg("a@s", "t1", 20, "texto")})
	rec := MediaRecord{ChatJID: "a@s", ID: "p1", Kind: KindImage, State: MediaThumb, Thumb: true, Proto: []byte{1, 2}}
	if err := s.SaveMedia(ctx, rec); err != nil {
		t.Fatal(err)
	}
	// Saving again keeps the first record (the history can repeat messages).
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a@s", ID: "p1", Kind: KindImage, State: MediaRemote, Proto: []byte{9}})

	page, _ := s.ListMessages(ctx, "a@s", 0, 10)
	if page[0].Media != MediaThumb || !page[0].Thumb || page[1].Media != "" || page[1].Thumb {
		t.Fatalf("listed = %+v", page)
	}
	got, err := s.Media(ctx, "a@s", "p1")
	if err != nil || got.State != MediaThumb || len(got.Proto) != 2 {
		t.Fatalf("Media = %+v, %v", got, err)
	}
	s.SetMediaState(ctx, "a@s", "p1", MediaDownloaded)
	if m, _ := s.Message(ctx, "a@s", "p1"); m.Media != MediaDownloaded {
		t.Fatalf("after download: %+v", m)
	}
	if _, err := s.Media(ctx, "a@s", "nope"); err != ErrNotFound {
		t.Fatalf("err = %v", err)
	}
}

func TestSettingsAndClear(t *testing.T) {
	s, ctx := open(t), context.Background()
	if v, _ := s.Setting(ctx, "x"); v != "" {
		t.Fatal("missing setting not empty")
	}
	s.SetSetting(ctx, "x", "1")
	s.SetSetting(ctx, "x", "2")
	if v, _ := s.Setting(ctx, "x"); v != "2" {
		t.Fatalf("setting = %q", v)
	}
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a", ID: "1", Kind: KindImage, State: MediaRemote, Proto: []byte{1}})
	s.Clear(ctx)
	if v, _ := s.Setting(ctx, "x"); v != "" {
		t.Fatal("settings survived Clear")
	}
	if _, err := s.Media(ctx, "a", "1"); err != ErrNotFound {
		t.Fatal("media survived Clear")
	}
}

func TestMediaDetailsAndForwardedMark(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.Save(ctx, []Message{{ChatJID: "a@s", ID: "d1", Kind: KindDocument, Timestamp: 10, Forwarded: true}})
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a@s", ID: "d1", Kind: KindDocument, State: MediaRemote,
		FileName: "contrato.pdf", Mime: "application/pdf", Size: 12345})
	s.Save(ctx, []Message{{ChatJID: "a@s", ID: "v1", Kind: KindAudio, Timestamp: 20}})
	s.SaveMedia(ctx, MediaRecord{ChatJID: "a@s", ID: "v1", Kind: KindAudio, State: MediaRemote,
		Mime: "audio/ogg; codecs=opus", Seconds: 7, PTT: true})

	page, _ := s.ListMessages(ctx, "a@s", 0, 10)
	if d := page[0]; d.FileName != "contrato.pdf" || d.Mime != "application/pdf" || d.Size != 12345 || !d.Forwarded {
		t.Fatalf("document = %+v", d)
	}
	if v := page[1]; v.Seconds != 7 || !v.PTT || v.Forwarded {
		t.Fatalf("voice = %+v", v)
	}
	// A media of mine gets its download data once uploaded.
	if err := s.SetMediaProto(ctx, "a@s", "v1", []byte{4, 2}); err != nil {
		t.Fatal(err)
	}
	if rec, _ := s.Media(ctx, "a@s", "v1"); len(rec.Proto) != 2 || rec.Seconds != 7 {
		t.Fatalf("record = %+v", rec)
	}
}

func TestMissingSearchIndexIsRebuiltOnOpen(t *testing.T) {
	path := filepath.Join(t.TempDir(), "wa.db")
	db, _ := sql.Open("sqlite3", "file:"+path)
	defer db.Close()
	ctx := context.Background()
	s, err := Open(ctx, db)
	if err != nil {
		t.Fatal(err)
	}
	s.Save(ctx, []Message{msg("a@s", "t1", 10, "orçamento aprovado")})
	// What the encryption of an old plain database leaves.
	if _, err := db.Exec(`DROP TRIGGER cc_messages_fts_bd; DROP TRIGGER cc_messages_fts_bu;
		DROP TRIGGER cc_messages_fts_ai; DROP TRIGGER cc_messages_fts_au; DROP TABLE cc_messages_fts;`); err != nil {
		t.Fatal(err)
	}
	if s, err = Open(ctx, db); err != nil {
		t.Fatal(err)
	}
	if found, _ := s.Search(ctx, "orcamento", 10); len(found) != 1 {
		t.Fatalf("search after rebuild = %+v", found)
	}
}
