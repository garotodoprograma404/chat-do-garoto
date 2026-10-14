// Package pinseal seals a secret (the app.db key) with a key derived from
// the user's PIN: Argon2id derives the key, AES-256-GCM
// seals. The PIN itself is never stored, not even as a hash.
package pinseal

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"errors"

	"golang.org/x/crypto/argon2"
)

// Argon2id parameters: RFC 9106's second recommended option, for devices
// with little memory. Stored in every envelope so they can grow later.
const (
	memoryKiB = 64 * 1024
	passes    = 3
	lanes     = 1
)

const (
	version   = 1
	saltBytes = 16
	keyBytes  = 32
	// version(1) memory(4) passes(4) lanes(1) salt(16)
	headerBytes = 1 + 4 + 4 + 1 + saltBytes
)

// ErrWrongPIN means the PIN does not open the envelope (or the envelope was
// altered: AES-GCM cannot tell the two apart, and neither should callers).
var ErrWrongPIN = errors.New("wrong PIN")

// ErrMalformed means the envelope is not one of ours.
var ErrMalformed = errors.New("malformed envelope")

// Seal returns a base64 envelope with secret sealed under pin.
func Seal(pin, secret []byte) (string, error) {
	header := make([]byte, headerBytes)
	header[0] = version
	binary.BigEndian.PutUint32(header[1:], memoryKiB)
	binary.BigEndian.PutUint32(header[5:], passes)
	header[9] = lanes
	if _, err := rand.Read(header[10:]); err != nil {
		return "", err
	}
	aead, err := newAEAD(pin, header)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, aead.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return "", err
	}
	// The header is authenticated: changing the parameters or the salt
	// breaks the envelope.
	out := append(append(header, nonce...), aead.Seal(nil, nonce, secret, header)...)
	return base64.StdEncoding.EncodeToString(out), nil
}

// Open returns the secret sealed in envelope, or ErrWrongPIN.
func Open(pin []byte, envelope string) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(envelope)
	if err != nil || len(raw) < headerBytes || raw[0] != version {
		return nil, ErrMalformed
	}
	header := raw[:headerBytes]
	aead, err := newAEAD(pin, header)
	if err != nil {
		return nil, err
	}
	rest := raw[headerBytes:]
	if len(rest) < aead.NonceSize()+aead.Overhead() {
		return nil, ErrMalformed
	}
	secret, err := aead.Open(nil, rest[:aead.NonceSize()], rest[aead.NonceSize():], header)
	if err != nil {
		return nil, ErrWrongPIN
	}
	return secret, nil
}

// newAEAD derives the AES-256-GCM key from pin and the header's parameters.
func newAEAD(pin, header []byte) (cipher.AEAD, error) {
	memory := binary.BigEndian.Uint32(header[1:])
	time := binary.BigEndian.Uint32(header[5:])
	threads := header[9]
	// Refuse absurd parameters from a tampered envelope (memory or time
	// bombs) before running Argon2id.
	if memory < 8*1024 || memory > 1024*1024 || time < 1 || time > 10 || threads < 1 || threads > 4 {
		return nil, ErrMalformed
	}
	key := argon2.IDKey(pin, header[10:headerBytes], time, memory, threads, keyBytes)
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
