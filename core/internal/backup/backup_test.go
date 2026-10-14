package backup

import (
	"archive/tar"
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"filippo.io/age"
)

const password = "senha forte 123"

func TestMain(m *testing.M) {
	workFactor = 10 // fast tests; the real one is 18
	os.Exit(m.Run())
}

// sample writes the files of a backup and returns them.
func sample(t *testing.T) []File {
	t.Helper()
	dir := t.TempDir()
	write := func(name string, data []byte) string {
		p := filepath.Join(dir, strings.ReplaceAll(name, "/", "_"))
		if err := os.WriteFile(p, data, 0o600); err != nil {
			t.Fatal(err)
		}
		return p
	}
	media := "media/" + strings.Repeat("ab", 32) + ".age"
	return []File{
		{Name: AppDBName, Path: write(AppDBName, []byte("segredo do crm"))},
		{Name: WaDBName, Path: write(WaDBName, bytes.Repeat([]byte("mensagens "), 50_000))},
		{Name: media, Path: write(media, []byte("foto cifrada"))},
	}
}

func written(t *testing.T, files []File, m Manifest) []byte {
	t.Helper()
	var out bytes.Buffer
	if err := Write(context.Background(), &out, password, m, files, nil); err != nil {
		t.Fatal(err)
	}
	return out.Bytes()
}

func TestRoundTrip(t *testing.T) {
	files := sample(t)
	var calls int
	var last, total int64
	var out bytes.Buffer
	err := Write(context.Background(), &out, password,
		Manifest{App: "0.1.0", AppSchema: 4, WaSchema: 7, Media: true, AppKey: "aa", WaKey: "bb"},
		files, func(d, tot int64) { calls++; last, total = d, tot })
	if err != nil {
		t.Fatal(err)
	}
	if calls == 0 || last != total || total < 500_000 {
		t.Fatalf("progress calls=%d last=%d total=%d", calls, last, total)
	}
	// Nothing readable in the file.
	for _, word := range []string{"segredo", "mensagens", "manifest", "app_key"} {
		if bytes.Contains(out.Bytes(), []byte(word)) {
			t.Fatalf("%q readable in the backup", word)
		}
	}
	dir := t.TempDir()
	m, err := Extract(context.Background(), bytes.NewReader(out.Bytes()), password, dir, 4, 7)
	if err != nil {
		t.Fatal(err)
	}
	if m.Format != FormatVersion || m.AppSchema != 4 || m.WaSchema != 7 || !m.Media ||
		m.AppKey != "aa" || m.WaKey != "bb" || m.CreatedAt == 0 || m.App != "0.1.0" {
		t.Fatalf("manifest = %+v", m)
	}
	for _, f := range files {
		want, _ := os.ReadFile(f.Path)
		got, err := os.ReadFile(filepath.Join(dir, filepath.FromSlash(f.Name)))
		if err != nil || !bytes.Equal(got, want) {
			t.Fatalf("%s differs: %v", f.Name, err)
		}
	}
}

// The file opens with age and the password, without the app.
func TestOpensWithAge(t *testing.T) {
	data := written(t, sample(t), Manifest{})
	id, _ := age.NewScryptIdentity(password)
	r, err := age.Decrypt(bytes.NewReader(data), id)
	if err != nil {
		t.Fatal(err)
	}
	tr := tar.NewReader(r)
	var names []string
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		names = append(names, h.Name)
	}
	if len(names) != 4 || names[0] != ManifestName {
		t.Fatalf("names = %v", names)
	}
}

func TestRefusals(t *testing.T) {
	ctx := context.Background()
	good := written(t, sample(t), Manifest{AppSchema: 4, WaSchema: 7})

	if _, err := Extract(ctx, bytes.NewReader(good), "outra senha", t.TempDir(), 4, 7); !errors.Is(err, ErrWrongPassword) {
		t.Fatalf("wrong password = %v", err)
	}
	if _, err := Extract(ctx, strings.NewReader("um PDF qualquer"), password, t.TempDir(), 4, 7); !errors.Is(err, ErrNotABackup) {
		t.Fatalf("not age = %v", err)
	}
	for _, cut := range []int{len(good) / 2, len(good) - 10} {
		if _, err := Extract(ctx, bytes.NewReader(good[:cut]), password, t.TempDir(), 4, 7); !errors.Is(err, ErrNotABackup) {
			t.Fatalf("cut at %d = %v", cut, err)
		}
	}
	if _, err := Extract(ctx, bytes.NewReader(good), password, t.TempDir(), 3, 7); !errors.Is(err, ErrNewerVersion) {
		t.Fatalf("newer app.db = %v", err)
	}
	if _, err := Extract(ctx, bytes.NewReader(good), password, t.TempDir(), 4, 6); !errors.Is(err, ErrNewerVersion) {
		t.Fatalf("newer wa.db = %v", err)
	}
	// An age file with a password but without our content.
	var other bytes.Buffer
	r, _ := age.NewScryptRecipient(password)
	r.SetWorkFactor(10)
	w, _ := age.Encrypt(&other, r)
	w.Write([]byte("not a tar"))
	w.Close()
	if _, err := Extract(ctx, bytes.NewReader(other.Bytes()), password, t.TempDir(), 4, 7); !errors.Is(err, ErrNotABackup) {
		t.Fatalf("other age file = %v", err)
	}
	if err := Write(ctx, io.Discard, "curta", Manifest{}, nil, nil); !errors.Is(err, ErrWeakPassword) {
		t.Fatalf("short password = %v", err)
	}
}

// Names outside the layout (a path escaping the folder, for example) make
// the file invalid.
func TestUnexpectedNamesAreRefused(t *testing.T) {
	for _, name := range []string{"../fora", "media/../../x.age", "outro.txt"} {
		files := append(sample(t), File{Name: name, Path: sample(t)[0].Path})
		data := written(t, files, Manifest{})
		dir := t.TempDir()
		if _, err := Extract(context.Background(), bytes.NewReader(data), password, dir, 9, 9); !errors.Is(err, ErrNotABackup) {
			t.Fatalf("%s = %v", name, err)
		}
		if _, err := os.Stat(filepath.Join(filepath.Dir(dir), "fora")); err == nil {
			t.Fatal("wrote outside the folder")
		}
	}
}

func TestCancel(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := Write(ctx, io.Discard, password, Manifest{}, sample(t), nil); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v", err)
	}
}
