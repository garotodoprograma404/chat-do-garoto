package vault

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func open(t *testing.T) (*Vault, string) {
	t.Helper()
	identity, err := NewIdentity()
	if err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(t.TempDir(), "media")
	v, err := Open(dir, identity)
	if err != nil {
		t.Fatal(err)
	}
	return v, dir
}

var jpeg = append([]byte{0xFF, 0xD8, 0xFF, 0xE0}, bytes.Repeat([]byte("photo"), 50000)...)

func TestPutAndGet(t *testing.T) {
	v, dir := open(t)
	name := Name("a@s.whatsapp.net", "ID1", "full")
	if err := v.Put(name, jpeg); err != nil {
		t.Fatal(err)
	}
	got, err := v.Get(name)
	if err != nil || !bytes.Equal(got, jpeg) {
		t.Fatalf("Get = %d bytes, %v", len(got), err)
	}

	// On disk: one encrypted file, nothing that looks like the photo.
	entries, _ := os.ReadDir(dir)
	if len(entries) != 1 {
		t.Fatalf("files in the vault: %d, want 1 (no temporary left)", len(entries))
	}
	raw, _ := os.ReadFile(filepath.Join(dir, entries[0].Name()))
	if bytes.HasPrefix(raw, []byte{0xFF, 0xD8, 0xFF}) || bytes.Contains(raw, []byte("photophoto")) {
		t.Fatal("the file on disk shows the photo")
	}
	if !bytes.HasPrefix(raw, []byte("age-encryption.org/v1")) {
		t.Fatalf("not an age file: %q", raw[:20])
	}
}

func TestNamesHideIDs(t *testing.T) {
	a := Name("a@s.whatsapp.net", "ID1", "thumb")
	if a == Name("a@s.whatsapp.net", "ID1", "full") || a == Name("a@s.whatsapp.net", "ID2", "thumb") {
		t.Fatal("names collide")
	}
	if bytes.Contains([]byte(a), []byte("ID1")) || len(a) != 64 {
		t.Fatalf("name %q", a)
	}
}

func TestAlteredFileIsRefused(t *testing.T) {
	v, dir := open(t)
	name := Name("c", "i", "full")
	v.Put(name, jpeg)
	p := filepath.Join(dir, name+".age")
	raw, _ := os.ReadFile(p)
	raw[len(raw)-10] ^= 1
	os.WriteFile(p, raw, 0o600)
	if _, err := v.Get(name); err == nil {
		t.Fatal("altered file decrypted")
	}
}

func TestAnotherIdentityCannotRead(t *testing.T) {
	v, dir := open(t)
	name := Name("c", "i", "thumb")
	v.Put(name, jpeg)
	other, _ := NewIdentity()
	w, _ := Open(dir, other)
	if _, err := w.Get(name); err == nil {
		t.Fatal("another identity read the file")
	}
	if _, err := Open(dir, "not an identity"); err == nil {
		t.Fatal("invalid identity accepted")
	}
}

func TestMissingAndClear(t *testing.T) {
	v, dir := open(t)
	if _, err := v.Get("nope"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("err = %v", err)
	}
	v.Put(Name("c", "1", "thumb"), []byte("a"))
	v.Put(Name("c", "2", "thumb"), []byte("b"))
	if !v.Has(Name("c", "1", "thumb")) {
		t.Fatal("Has = false")
	}
	if err := v.Clear(); err != nil {
		t.Fatal(err)
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 0 {
		t.Fatalf("%d files after Clear", len(entries))
	}
}

func TestDelete(t *testing.T) {
	v, _ := open(t)
	v.Put(Name("c", "1", "full"), []byte("a"))
	if err := v.Delete(Name("c", "1", "full")); err != nil {
		t.Fatal(err)
	}
	if v.Has(Name("c", "1", "full")) {
		t.Fatal("still there")
	}
	if err := v.Delete(Name("c", "1", "full")); err != nil {
		t.Fatalf("missing file: %v", err)
	}
}

func TestFilesAndReplace(t *testing.T) {
	v, _ := open(t)
	v.Put(Name("c", "1", "full"), []byte("velha"))
	src := t.TempDir()
	other, _ := Open(src, mustIdentity(t, v))
	other.Put(Name("c", "2", "full"), []byte("nova"))
	os.WriteFile(filepath.Join(src, "lixo.txt"), []byte("x"), 0o600)
	if err := v.Replace(src); err != nil {
		t.Fatal(err)
	}
	files, _ := v.Files()
	if len(files) != 1 || v.Has(Name("c", "1", "full")) {
		t.Fatalf("files = %v", files)
	}
	if got, err := v.Get(Name("c", "2", "full")); err != nil || string(got) != "nova" {
		t.Fatalf("got %q, %v", got, err)
	}
}

func mustIdentity(t *testing.T, v *Vault) string {
	t.Helper()
	return v.id.String()
}
