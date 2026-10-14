package pinseal

import (
	"bytes"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"testing"
)

var secret = bytes.Repeat([]byte{0xab}, 32)

func TestSealAndOpen(t *testing.T) {
	env, err := Seal([]byte("123456"), secret)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Open([]byte("123456"), env)
	if err != nil || !bytes.Equal(got, secret) {
		t.Fatalf("Open = %x, %v", got, err)
	}
	if bytes.Contains([]byte(env), []byte("123456")) {
		t.Fatal("the envelope shows the PIN")
	}
}

func TestEnvelopesAreSalted(t *testing.T) {
	a, _ := Seal([]byte("123456"), secret)
	b, _ := Seal([]byte("123456"), secret)
	if a == b {
		t.Fatal("two envelopes of the same PIN are equal")
	}
}

func TestWrongPIN(t *testing.T) {
	env, _ := Seal([]byte("123456"), secret)
	if _, err := Open([]byte("654321"), env); !errors.Is(err, ErrWrongPIN) {
		t.Fatalf("err = %v, want ErrWrongPIN", err)
	}
}

func TestTamperingIsRefused(t *testing.T) {
	env, _ := Seal([]byte("123456"), secret)
	raw, _ := base64.StdEncoding.DecodeString(env)

	flip := func(i int) string {
		c := bytes.Clone(raw)
		c[i] ^= 1
		return base64.StdEncoding.EncodeToString(c)
	}
	if _, err := Open([]byte("123456"), flip(len(raw)-1)); !errors.Is(err, ErrWrongPIN) {
		t.Errorf("altered ciphertext: %v", err)
	}
	if _, err := Open([]byte("123456"), flip(12)); !errors.Is(err, ErrWrongPIN) {
		t.Errorf("altered salt: %v", err)
	}

	// Parameters are authenticated, and absurd ones are refused outright.
	bomb := bytes.Clone(raw)
	binary.BigEndian.PutUint32(bomb[1:], 64*1024*1024)
	if _, err := Open([]byte("123456"), base64.StdEncoding.EncodeToString(bomb)); !errors.Is(err, ErrMalformed) {
		t.Errorf("memory bomb: %v", err)
	}
	for _, bad := range []string{"", "not base64!", base64.StdEncoding.EncodeToString([]byte{9, 9, 9})} {
		if _, err := Open([]byte("123456"), bad); !errors.Is(err, ErrMalformed) {
			t.Errorf("Open(%q) = %v, want ErrMalformed", bad, err)
		}
	}
}

func TestParametersAreStored(t *testing.T) {
	env, _ := Seal([]byte("123456"), secret)
	raw, _ := base64.StdEncoding.DecodeString(env)
	if raw[0] != version || binary.BigEndian.Uint32(raw[1:]) != memoryKiB ||
		binary.BigEndian.Uint32(raw[5:]) != passes || raw[9] != lanes {
		t.Fatalf("header = %x", raw[:10])
	}
}
