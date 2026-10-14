// Package bridge holds the parts of the C API that do not need cgo: the JSON
// envelope returned to the app, panic recovery, and the counter of strings
// still owned by the caller. See include/chatcore.h for the contract.
package bridge

import (
	"encoding/json"
	"errors"
	"sync/atomic"
)

// ProtocolVersion is the "v" field of every envelope.
const ProtocolVersion = 1

// CoreVersion is the version of the Go core reported by cc_version.
const CoreVersion = "0.1.0"

// Error codes that can cross the bridge.
const (
	CodeInvalidArgument = "invalid_argument"
	CodeInternal        = "internal"
)

// internalMessage is the only message sent for unexpected failures: panic
// values and plain errors may carry user data, so they never cross the bridge.
const internalMessage = "unexpected failure in core"

// Error is a failure whose code and message are safe to show to the app.
// Only errors of this type keep their message when crossing the bridge.
type Error struct {
	Code    string
	Message string
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }

type envelope struct {
	V     int        `json:"v"`
	OK    bool       `json:"ok"`
	Data  any        `json:"data,omitempty"`
	Error *errorBody `json:"error,omitempty"`
}

type errorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Call runs fn and encodes its outcome as a JSON envelope. A panic inside fn
// becomes an "internal" error instead of crashing the host app.
func Call(fn func() (any, error)) (out []byte) {
	defer func() {
		if recover() != nil {
			out = encodeError(CodeInternal, internalMessage)
		}
	}()

	data, err := fn()
	if err != nil {
		var bridgeErr *Error
		if errors.As(err, &bridgeErr) {
			return encodeError(bridgeErr.Code, bridgeErr.Message)
		}
		return encodeError(CodeInternal, internalMessage)
	}
	return encode(envelope{V: ProtocolVersion, OK: true, Data: data})
}

func encodeError(code, message string) []byte {
	return encode(envelope{V: ProtocolVersion, Error: &errorBody{Code: code, Message: message}})
}

func encode(e envelope) []byte {
	b, err := json.Marshal(e)
	if err != nil {
		return []byte(`{"v":1,"ok":false,"error":{"code":"internal","message":"` + internalMessage + `"}}`)
	}
	return b
}

var liveAllocs atomic.Int64

// NoteAlloc records that a string was handed to the caller.
func NoteAlloc() { liveAllocs.Add(1) }

// NoteFree records that the caller released a string.
func NoteFree() { liveAllocs.Add(-1) }

// LiveAllocs returns how many strings the caller still holds.
func LiveAllocs() int64 { return liveAllocs.Load() }
