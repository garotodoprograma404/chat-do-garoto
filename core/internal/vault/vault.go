// Package vault keeps media files encrypted on disk with the age format
// : one X25519 identity per install, kept inside the
// encrypted wa.db. Plaintext only ever exists in memory.
package vault

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"

	"filippo.io/age"
)

// ErrNotFound means the vault has no file under that name.
var ErrNotFound = errors.New("not in the vault")

// Vault stores files encrypted to one age identity.
type Vault struct {
	dir string
	id  *age.X25519Identity
}

// NewIdentity returns a new age identity, as text, to keep in wa.db.
func NewIdentity() (string, error) {
	id, err := age.GenerateX25519Identity()
	if err != nil {
		return "", err
	}
	return id.String(), nil
}

// Open returns the vault in dir for identity (from NewIdentity).
func Open(dir, identity string) (*Vault, error) {
	id, err := age.ParseX25519Identity(identity)
	if err != nil {
		return nil, errors.New("vault: invalid identity") // never echo it
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	return &Vault{dir: dir, id: id}, nil
}

// Name is the file name of one media part ("thumb" or "full") of a
// message: a hash, so message IDs do not show on disk.
func Name(chat, id, part string) string {
	sum := sha256.Sum256([]byte(chat + "\x00" + id + "\x00" + part))
	return hex.EncodeToString(sum[:])
}

func (v *Vault) path(name string) string { return filepath.Join(v.dir, name+".age") }

// Put encrypts data under name, replacing any previous file atomically.
func (v *Vault) Put(name string, data []byte) error {
	tmp, err := os.CreateTemp(v.dir, ".put-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name()) // no-op after the rename
	w, err := age.Encrypt(tmp, v.id.Recipient())
	if err == nil {
		_, err = w.Write(data)
	}
	if err == nil {
		err = w.Close()
	}
	if err == nil {
		err = tmp.Sync()
	}
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return err
	}
	return os.Rename(tmp.Name(), v.path(name))
}

// Get decrypts the file under name into memory.
func (v *Vault) Get(name string) ([]byte, error) {
	f, err := os.Open(v.path(name))
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	defer f.Close()
	r, err := age.Decrypt(f, v.id)
	if err != nil {
		return nil, err
	}
	var out bytes.Buffer
	if _, err := io.Copy(&out, r); err != nil {
		return nil, err // altered or truncated file
	}
	return out.Bytes(), nil
}

// Has reports whether name is in the vault.
func (v *Vault) Has(name string) bool {
	_, err := os.Stat(v.path(name))
	return err == nil
}

// Delete removes the file under name; a missing file is not an error.
func (v *Vault) Delete(name string) error {
	err := os.Remove(v.path(name))
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}

// Dir is the folder of the vault.
func (v *Vault) Dir() string { return v.dir }

// Files lists the paths of the vault's files, for a backup.
func (v *Vault) Files() ([]string, error) {
	entries, err := os.ReadDir(v.dir)
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if e.Type().IsRegular() && filepath.Ext(e.Name()) == ".age" {
			out = append(out, filepath.Join(v.dir, e.Name()))
		}
	}
	return out, nil
}

// Replace empties the vault and moves into it the .age files of src, from
// a restored backup. They must be encrypted to the vault's identity.
func (v *Vault) Replace(src string) error {
	if err := v.Clear(); err != nil {
		return err
	}
	entries, err := os.ReadDir(src)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if !e.Type().IsRegular() || filepath.Ext(e.Name()) != ".age" {
			continue
		}
		if err := os.Rename(filepath.Join(src, e.Name()), filepath.Join(v.dir, e.Name())); err != nil {
			return err
		}
	}
	return nil
}

// Clear deletes every file of the vault (unlinking the device R6).
func (v *Vault) Clear() error {
	entries, err := os.ReadDir(v.dir)
	if err != nil {
		return err
	}
	for _, e := range entries {
		if err := os.Remove(filepath.Join(v.dir, e.Name())); err != nil {
			return err
		}
	}
	return nil
}
