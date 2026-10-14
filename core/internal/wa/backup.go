package wa

import (
	"bufio"
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"time"

	"chatdogaroto/core/internal/backup"
	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

// Backup events and error codes.
const (
	EventBackupProgress = "backup_progress" // {"done", "total"} in bytes
	EventBackupDone     = "backup_done"     // {"bytes"}
	EventBackupReady    = "backup_ready"    // {"app_copy", "app_key", "app_schema", "media", "created_at"}
	EventBackupRestored = "backup_restored" // the conversations and media are back
	EventBackupFailed   = "backup_failed"   // {"code"}

	CodeWrongPassword = "wrong_password"
	CodeNotABackup    = "not_a_backup"
	CodeNewerVersion  = "newer_version"
	CodeWeakPassword  = "weak_password"
	CodeCancelled     = "cancelled"
	CodeFailed        = "failed"
	CodeBusy          = "busy"
)

// ExportRequest is what the app sends to make a backup. The app.db copy is
// already encrypted with AppKey; the core only copies its bytes.
type ExportRequest struct {
	Password   string `json:"password"`
	AppCopy    string `json:"app_copy"`
	AppKey     string `json:"app_key"`
	AppVersion string `json:"app_version"`
	AppSchema  int    `json:"app_schema"`
	Media      bool   `json:"media"`
	WorkDir    string `json:"work_dir"`
}

// OpenRequest is what the app sends to open a backup to restore.
type OpenRequest struct {
	Password     string `json:"password"`
	WorkDir      string `json:"work_dir"`
	MaxAppSchema int    `json:"max_app_schema"`
}

// restoring is a backup opened and checked, waiting for BackupCommit.
type restoring struct {
	dir string
	m   backup.Manifest
}

var oneTimeKey = regexp.MustCompile(`^[0-9a-f]{64}$`)

// newKey returns a random one-time key for a database copy.
func newKey() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// openCopy opens a database copy with its one-time key (Go's own files
// only, never the app's: invariant 5).
func openCopy(path, key string) (*sql.DB, error) {
	return sql.Open("sqlite3", dsn(path, key))
}

// startBackupTask reserves the single backup slot.
func (s *Session) startBackupTask() (context.Context, error) {
	s.backupMu.Lock()
	defer s.backupMu.Unlock()
	if s.backupCancel != nil {
		return nil, &bridge.Error{Code: CodeBusy, Message: "a backup is running"}
	}
	ctx, cancel := context.WithCancel(context.Background())
	s.backupCancel = cancel
	return ctx, nil
}

func (s *Session) endBackupTask() {
	s.backupMu.Lock()
	defer s.backupMu.Unlock()
	if s.backupCancel != nil {
		s.backupCancel()
		s.backupCancel = nil
	}
}

// BackupCancel stops the backup or the opening running now, if any.
func (s *Session) BackupCancel() {
	s.backupMu.Lock()
	defer s.backupMu.Unlock()
	if s.backupCancel != nil {
		s.backupCancel()
	}
}

func (s *Session) stores() (*msgstore.Store, *vault.Vault, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.msgs == nil {
		return nil, nil, invalidState("call cc_wa_start first")
	}
	return s.msgs, s.media, nil
}

// BackupExport writes the backup to the file descriptor fd (the file the
// user picked), in the background; it ends as backup_done or backup_failed.
// The core takes fd and closes it.
func (s *Session) BackupExport(fd int, req ExportRequest) error {
	out := os.NewFile(uintptr(fd), "backup")
	if out == nil {
		return invalidArgument("invalid file")
	}
	fail := func(err error) error { out.Close(); return err }
	if len([]rune(req.Password)) < backup.MinPassword {
		return fail(&bridge.Error{Code: CodeWeakPassword, Message: "password too short"})
	}
	if !oneTimeKey.MatchString(req.AppKey) || req.AppCopy == "" || req.WorkDir == "" {
		return fail(invalidArgument("invalid backup request"))
	}
	msgs, media, err := s.stores()
	if err != nil {
		return fail(err)
	}
	ctx, err := s.startBackupTask()
	if err != nil {
		return fail(err)
	}
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		defer s.endBackupTask()
		n, err := s.writeBackup(ctx, out, req, msgs, media)
		if cerr := out.Close(); err == nil {
			err = cerr
		}
		os.Remove(req.AppCopy)
		if err != nil {
			code := CodeFailed
			if errors.Is(err, context.Canceled) {
				code = CodeCancelled
			}
			s.hub.Emit(EventBackupFailed, map[string]any{"code": code})
			return
		}
		s.hub.Emit(EventBackupDone, map[string]any{"bytes": n})
	}()
	return nil
}

func (s *Session) writeBackup(ctx context.Context, out *os.File, req ExportRequest, msgs *msgstore.Store, media *vault.Vault) (int64, error) {
	if err := os.MkdirAll(req.WorkDir, 0o700); err != nil {
		return 0, err
	}
	waKey, err := newKey()
	if err != nil {
		return 0, err
	}
	waCopy := filepath.Join(req.WorkDir, "wa.db")
	removeDB(waCopy)
	defer removeDB(waCopy)
	if err := msgs.ExportTo(ctx, waCopy, waKey, openCopy); err != nil {
		return 0, err
	}
	files := []backup.File{
		{Name: backup.AppDBName, Path: req.AppCopy},
		{Name: backup.WaDBName, Path: waCopy},
	}
	if req.Media && media != nil {
		paths, err := media.Files()
		if err != nil {
			return 0, err
		}
		for _, p := range paths {
			files = append(files, backup.File{Name: backup.MediaDir + filepath.Base(p), Path: p})
		}
	}
	m := backup.Manifest{
		App: req.AppVersion, AppSchema: req.AppSchema, WaSchema: msgstore.SchemaVersion(),
		Media: req.Media, AppKey: req.AppKey, WaKey: waKey,
	}
	w := &counter{w: bufio.NewWriterSize(out, 1<<20)}
	var last time.Time
	err = backup.Write(ctx, w, req.Password, m, files, func(done, total int64) {
		if now := time.Now(); now.Sub(last) > 250*time.Millisecond || done == total {
			last = now
			s.hub.Emit(EventBackupProgress, map[string]any{"done": done, "total": total})
		}
	})
	if err == nil {
		err = w.w.(*bufio.Writer).Flush()
	}
	return w.n, err
}

// BackupOpen reads and checks the backup in fd with password, in the
// background, into the work folder; it ends as backup_ready (with the
// app.db copy for the app to import) or backup_failed. Nothing changes
// until BackupCommit. The core takes fd and closes it.
func (s *Session) BackupOpen(fd int, req OpenRequest) error {
	in := os.NewFile(uintptr(fd), "backup")
	if in == nil {
		return invalidArgument("invalid file")
	}
	if req.WorkDir == "" {
		in.Close()
		return invalidArgument("invalid backup request")
	}
	if _, _, err := s.stores(); err != nil {
		in.Close()
		return err
	}
	ctx, err := s.startBackupTask()
	if err != nil {
		in.Close()
		return err
	}
	s.BackupDiscard()
	dir := filepath.Join(req.WorkDir, "restore")
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		defer s.endBackupTask()
		os.RemoveAll(dir)
		m, err := backup.Extract(ctx, bufio.NewReaderSize(in, 1<<20), req.Password, dir,
			req.MaxAppSchema, msgstore.SchemaVersion())
		in.Close()
		if err != nil {
			os.RemoveAll(dir)
			s.hub.Emit(EventBackupFailed, map[string]any{"code": openError(err)})
			return
		}
		s.backupMu.Lock()
		s.restore = &restoring{dir: dir, m: m}
		s.backupMu.Unlock()
		s.hub.Emit(EventBackupReady, map[string]any{
			"app_copy": filepath.Join(dir, backup.AppDBName), "app_key": m.AppKey,
			"app_schema": m.AppSchema, "media": m.Media, "created_at": m.CreatedAt,
		})
	}()
	return nil
}

func openError(err error) string {
	switch {
	case errors.Is(err, backup.ErrWrongPassword):
		return CodeWrongPassword
	case errors.Is(err, backup.ErrNotABackup):
		return CodeNotABackup
	case errors.Is(err, backup.ErrNewerVersion):
		return CodeNewerVersion
	case errors.Is(err, context.Canceled):
		return CodeCancelled
	}
	return CodeFailed
}

// BackupCommit replaces the conversations and the media with the opened
// backup, in the background (after the app imported its app.db copy); it
// ends as backup_restored or backup_failed. On failure the opened backup
// stays, so it can be tried again.
func (s *Session) BackupCommit() error {
	s.backupMu.Lock()
	r := s.restore
	s.backupMu.Unlock()
	if r == nil {
		return invalidState("no backup opened")
	}
	msgs, media, err := s.stores()
	if err != nil {
		return err
	}
	ctx, err := s.startBackupTask()
	if err != nil {
		return err
	}
	s.sends.Add(1)
	go func() {
		defer s.sends.Done()
		defer s.endBackupTask()
		if err := s.commit(ctx, r, msgs, media); err != nil {
			s.hub.Emit(EventBackupFailed, map[string]any{"code": CodeFailed})
			return
		}
		s.BackupDiscard()
		s.hub.Emit(EventHistory, map[string]any{"chats": 0, "messages": 0}) // reload the lists
		s.hub.Emit(EventBackupRestored, nil)
	}()
	return nil
}

func (s *Session) commit(ctx context.Context, r *restoring, msgs *msgstore.Store, media *vault.Vault) error {
	if err := msgs.ImportFrom(ctx, filepath.Join(r.dir, backup.WaDBName), r.m.WaKey, openCopy); err != nil {
		return err
	}
	// The media are encrypted to the backup's vault identity, restored
	// with the conversations: the vault opens again with it.
	dir := filepath.Join(filepath.Dir(r.dir), "media")
	if media != nil {
		dir = media.Dir()
	}
	v, err := openVault(ctx, msgs, dir)
	if err != nil {
		return err
	}
	if r.m.Media {
		err = v.Replace(filepath.Join(r.dir, "media"))
	} else {
		if err = v.Clear(); err == nil {
			err = msgs.ForgetMedia(ctx)
		}
	}
	if err != nil {
		return err
	}
	s.mu.Lock()
	if s.msgs == msgs {
		s.media = v
	}
	s.mu.Unlock()
	return nil
}

// BackupDiscard drops an opened backup that will not be restored.
func (s *Session) BackupDiscard() {
	s.backupMu.Lock()
	r := s.restore
	s.restore = nil
	s.backupMu.Unlock()
	if r != nil {
		os.RemoveAll(r.dir)
	}
}

// removeDB deletes a database copy and its journal files.
func removeDB(path string) {
	for _, suffix := range []string{"", "-wal", "-shm", "-journal"} {
		os.Remove(path + suffix)
	}
}

// counter counts the bytes written.
type counter struct {
	w interface{ Write([]byte) (int, error) }
	n int64
}

func (c *counter) Write(p []byte) (int, error) {
	n, err := c.w.Write(p)
	c.n += int64(n)
	return n, err
}
