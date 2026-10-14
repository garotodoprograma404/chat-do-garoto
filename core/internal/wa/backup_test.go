package wa

import (
	"context"
	"os"
	"path/filepath"
	"syscall"
	"testing"

	"chatdogaroto/core/internal/backup"
	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

const backupPassword = "senha do backup"

func init() { backup.SetWorkFactorForTests(10) }

// fdOf opens path (for writing or reading) and returns a descriptor the
// core may own and close, like the one Android hands over.
func fdOf(t *testing.T, path string, write bool) int {
	t.Helper()
	var f *os.File
	var err error
	if write {
		f, err = os.Create(path)
	} else {
		f, err = os.Open(path)
	}
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	fd, err := syscall.Dup(int(f.Fd()))
	if err != nil {
		t.Fatal(err)
	}
	return fd
}

func exportBackup(t *testing.T, s *Session, media bool) string {
	t.Helper()
	work := t.TempDir()
	appCopy := filepath.Join(work, "app.db")
	os.WriteFile(appCopy, []byte("copia do app.db"), 0o600)
	out := filepath.Join(t.TempDir(), "chatdogaroto.backup")
	key, _ := newKey()
	if err := s.BackupExport(fdOf(t, out, true), ExportRequest{
		Password: backupPassword, AppCopy: appCopy, AppKey: key, AppVersion: "0.1.0",
		AppSchema: 4, Media: media, WorkDir: work,
	}); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
	if _, err := os.Stat(appCopy); err == nil {
		t.Fatal("app.db copy left behind")
	}
	if left, _ := os.ReadDir(work); len(left) != 0 {
		t.Fatalf("work files left: %v", left)
	}
	return out
}

func openBackup(t *testing.T, s *Session, path, password string) {
	t.Helper()
	if err := s.BackupOpen(fdOf(t, path, false), OpenRequest{Password: password, WorkDir: t.TempDir(), MaxAppSchema: 4}); err != nil {
		t.Fatal(err)
	}
	s.sends.Wait()
}

func TestBackupAndRestore(t *testing.T) {
	src, _, got := offlineSession(t)
	withPhoto(t, src)
	src.msgs.SetChatName(context.Background(), alice.String(), "Alice")
	out := exportBackup(t, src, true)
	if typ, data := lastEvent(got); typ != EventBackupDone || data["bytes"].(float64) <= 0 {
		t.Fatalf("event = %s %v", typ, data)
	}
	var progress bool
	for _, e := range *got {
		progress = progress || e["type"] == EventBackupProgress
	}
	if !progress {
		t.Fatal("no progress")
	}

	dst, _, dgot := offlineSession(t)
	dst.msgs.Save(context.Background(), []msgstore.Message{{ChatJID: bob.String(), ID: "X", Kind: msgstore.KindText, Text: "deste aparelho", Timestamp: 1}})
	openBackup(t, dst, out, backupPassword)
	typ, data := lastEvent(dgot)
	if typ != EventBackupReady || data["media"] != true || data["app_schema"].(float64) != 4 {
		t.Fatalf("event = %s %v", typ, data)
	}
	if b, _ := os.ReadFile(data["app_copy"].(string)); string(b) != "copia do app.db" {
		t.Fatalf("app copy = %q", b)
	}
	// Nothing changes before the commit.
	if chats, _ := dst.ListChats(10); len(chats) != 1 || chats[0].JID != bob.String() {
		t.Fatalf("changed before commit: %+v", chats)
	}
	if err := dst.BackupCommit(); err != nil {
		t.Fatal(err)
	}
	dst.sends.Wait()
	if typ, _ := lastEvent(dgot); typ != EventBackupRestored {
		t.Fatalf("event = %s", typ)
	}
	chats, _ := dst.ListChats(10)
	if len(chats) != 1 || chats[0].Name != "Alice" {
		t.Fatalf("chats = %+v", chats)
	}
	full, err := dst.media.Get(vault.Name(alice.String(), "P1", PartFull))
	if err != nil || string(full) != "full" {
		t.Fatalf("media = %q, %v", full, err)
	}
	if err := dst.BackupCommit(); err == nil {
		t.Fatal("committed twice")
	}
}

func TestRestoreWithoutMedia(t *testing.T) {
	src, _, _ := offlineSession(t)
	withPhoto(t, src)
	out := exportBackup(t, src, false)
	dst, _, _ := offlineSession(t)
	openBackup(t, dst, out, backupPassword)
	dst.BackupCommit()
	dst.sends.Wait()
	m, _ := dst.msgs.Message(context.Background(), alice.String(), "P1")
	if m.Media != msgstore.MediaExpired && m.Media != msgstore.MediaRemote {
		t.Fatalf("media = %+v", m)
	}
	if files, _ := dst.media.Files(); len(files) != 0 {
		t.Fatalf("vault = %v", files)
	}
}

func TestOpenRefusals(t *testing.T) {
	src, _, _ := offlineSession(t)
	out := exportBackup(t, src, true)
	dst, _, got := offlineSession(t)
	openBackup(t, dst, out, "senha errada!")
	if typ, data := lastEvent(got); typ != EventBackupFailed || data["code"] != CodeWrongPassword {
		t.Fatalf("event = %s %v", typ, data)
	}
	junk := filepath.Join(t.TempDir(), "x.pdf")
	os.WriteFile(junk, []byte("%PDF-1.4 qualquer"), 0o600)
	openBackup(t, dst, junk, backupPassword)
	if _, data := lastEvent(got); data["code"] != CodeNotABackup {
		t.Fatalf("event = %v", data)
	}
	if err := dst.BackupCommit(); err == nil {
		t.Fatal("commit without an opened backup")
	}
	// Short password and a malformed request never start.
	key, _ := newKey()
	if err := src.BackupExport(fdOf(t, filepath.Join(t.TempDir(), "b"), true), ExportRequest{Password: "curta", AppKey: key, AppCopy: "x", WorkDir: "y"}); err == nil {
		t.Fatal("short password accepted")
	}
	if err := src.BackupExport(fdOf(t, filepath.Join(t.TempDir(), "b"), true), ExportRequest{Password: backupPassword, AppKey: "nope", AppCopy: "x", WorkDir: "y"}); err == nil {
		t.Fatal("bad key accepted")
	}
	var empty Session
	if err := empty.BackupExport(fdOf(t, filepath.Join(t.TempDir(), "b"), true), ExportRequest{Password: backupPassword, AppKey: key, AppCopy: "x", WorkDir: "y"}); err == nil {
		t.Fatal("accepted before start")
	}
}
