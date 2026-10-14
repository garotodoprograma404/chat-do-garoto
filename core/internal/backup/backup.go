// Package backup writes and reads the app's encrypted backup file: a tar inside an age file encrypted with the user's password
// (scrypt). The databases inside are working copies encrypted with one-time
// keys; the media are the vault's files as they are (already age files).
package backup

import (
	"archive/tar"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"time"

	"filippo.io/age"
)

// FormatVersion is the version of this file layout. Newer files are
// refused; older ones must keep opening.
const FormatVersion = 1

// Names inside the backup.
const (
	ManifestName = "manifest.json"
	AppDBName    = "app.db"
	WaDBName     = "wa.db"
	MediaDir     = "media/"
)

// MinPassword is the shortest password accepted.
const MinPassword = 8

// workFactor is the scrypt cost (2^18, age's default). Tests lower it.
var workFactor = 18

// SetWorkFactorForTests makes the password check fast in other packages'
// tests. Never call it in the app.
func SetWorkFactorForTests(logN int) { workFactor = logN }

var (
	ErrWrongPassword = errors.New("wrong password")
	ErrNotABackup    = errors.New("not a backup of the app")
	ErrNewerVersion  = errors.New("backup from a newer app")
	ErrWeakPassword  = errors.New("password too short")
)

// Manifest describes a backup. The one-time keys of the database copies
// only exist inside the encrypted file.
type Manifest struct {
	Format    int    `json:"format"`
	App       string `json:"app"`        // app version that made it
	AppSchema int    `json:"app_schema"` // app.db version
	WaSchema  int    `json:"wa_schema"`  // version of wa.db's cc_* tables
	CreatedAt int64  `json:"created_at"` // Unix milliseconds
	Media     bool   `json:"media"`
	AppKey    string `json:"app_key"`
	WaKey     string `json:"wa_key"`
}

// File is one file to put in the backup.
type File struct {
	Name string // inside the backup
	Path string // on disk
}

// Progress reports bytes written so far out of total.
type Progress func(done, total int64)

// Write encrypts manifest and files into w with password. It stops with
// ctx.Err() when ctx is cancelled.
func Write(ctx context.Context, w io.Writer, password string, m Manifest, files []File, progress Progress) error {
	if len([]rune(password)) < MinPassword {
		return ErrWeakPassword
	}
	m.Format = FormatVersion
	if m.CreatedAt == 0 {
		m.CreatedAt = time.Now().UnixMilli()
	}
	var total int64
	for _, f := range files {
		info, err := os.Stat(f.Path)
		if err != nil {
			return err
		}
		total += info.Size()
	}
	r, err := age.NewScryptRecipient(password)
	if err != nil {
		return err
	}
	r.SetWorkFactor(workFactor)
	enc, err := age.Encrypt(w, r)
	if err != nil {
		return err
	}
	tw := tar.NewWriter(enc)
	manifest, err := json.Marshal(m)
	if err != nil {
		return err
	}
	if err := tw.WriteHeader(&tar.Header{Name: ManifestName, Mode: 0o600, Size: int64(len(manifest))}); err != nil {
		return err
	}
	if _, err := tw.Write(manifest); err != nil {
		return err
	}
	var done int64
	for _, f := range files {
		if err := addFile(ctx, tw, f, func(n int64) {
			done += n
			if progress != nil {
				progress(done, total)
			}
		}); err != nil {
			return err
		}
	}
	if err := tw.Close(); err != nil {
		return err
	}
	return enc.Close()
}

func addFile(ctx context.Context, tw *tar.Writer, f File, wrote func(int64)) error {
	in, err := os.Open(f.Path)
	if err != nil {
		return err
	}
	defer in.Close()
	info, err := in.Stat()
	if err != nil {
		return err
	}
	if err := tw.WriteHeader(&tar.Header{Name: f.Name, Mode: 0o600, Size: info.Size()}); err != nil {
		return err
	}
	buf := make([]byte, 256<<10)
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		n, rerr := in.Read(buf)
		if n > 0 {
			if _, err := tw.Write(buf[:n]); err != nil {
				return err
			}
			wrote(int64(n))
		}
		if rerr == io.EOF {
			return nil
		}
		if rerr != nil {
			return rerr
		}
	}
}

// mediaName is a vault file: the SHA-256 name and the age extension.
var mediaName = regexp.MustCompile(`^media/[0-9a-f]{64}\.age$`)

// Extract decrypts r with password into dir (app.db, wa.db and media/),
// checking the whole file before returning: age authenticates every chunk,
// up to the end. Backups whose databases are newer than maxAppSchema or
// maxWaSchema are refused.
func Extract(ctx context.Context, r io.Reader, password string, dir string, maxAppSchema, maxWaSchema int) (Manifest, error) {
	id, err := age.NewScryptIdentity(password)
	if err != nil {
		return Manifest{}, ErrWrongPassword // empty password
	}
	dec, err := age.Decrypt(r, id)
	if err != nil {
		// An age file the password does not open.
		var noMatch *age.NoIdentityMatchError
		if errors.As(err, &noMatch) || errors.Is(err, age.ErrIncorrectIdentity) {
			return Manifest{}, ErrWrongPassword
		}
		return Manifest{}, ErrNotABackup
	}
	tr := tar.NewReader(dec)
	hdr, err := tr.Next()
	if err != nil || hdr.Name != ManifestName || hdr.Size > 1<<20 {
		return Manifest{}, ErrNotABackup
	}
	var m Manifest
	if err := json.NewDecoder(io.LimitReader(tr, hdr.Size)).Decode(&m); err != nil || m.Format < 1 {
		return Manifest{}, ErrNotABackup
	}
	if m.Format > FormatVersion || m.AppSchema > maxAppSchema || m.WaSchema > maxWaSchema {
		return Manifest{}, ErrNewerVersion
	}
	if err := os.MkdirAll(filepath.Join(dir, MediaDir), 0o700); err != nil {
		return Manifest{}, err
	}
	seen := map[string]bool{}
	for {
		if err := ctx.Err(); err != nil {
			return Manifest{}, err
		}
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return Manifest{}, ErrNotABackup
		}
		if hdr.Typeflag != tar.TypeReg || seen[hdr.Name] ||
			(hdr.Name != AppDBName && hdr.Name != WaDBName && !mediaName.MatchString(hdr.Name)) {
			return Manifest{}, ErrNotABackup
		}
		seen[hdr.Name] = true
		if err := extractFile(tr, filepath.Join(dir, filepath.FromSlash(hdr.Name)), hdr.Size); err != nil {
			return Manifest{}, err
		}
	}
	// Read to the very end: the last chunk is authenticated there, so a cut
	// file fails here instead of passing.
	if _, err := io.Copy(io.Discard, dec); err != nil {
		return Manifest{}, ErrNotABackup
	}
	if !seen[AppDBName] || !seen[WaDBName] {
		return Manifest{}, ErrNotABackup
	}
	return m, nil
}

func extractFile(tr *tar.Reader, path string, size int64) error {
	out, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	n, err := io.Copy(out, tr)
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	if err != nil || n != size {
		return fmt.Errorf("%w: %v", ErrNotABackup, err)
	}
	return nil
}
