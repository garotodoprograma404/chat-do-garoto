package bridge

import (
	"encoding/json"
	"errors"
	"testing"
)

type decoded struct {
	V     int            `json:"v"`
	OK    bool           `json:"ok"`
	Data  map[string]any `json:"data"`
	Error *errorBody     `json:"error"`
}

func decode(t *testing.T, b []byte) decoded {
	t.Helper()
	var d decoded
	if err := json.Unmarshal(b, &d); err != nil {
		t.Fatalf("invalid envelope %q: %v", b, err)
	}
	if d.V != ProtocolVersion {
		t.Fatalf("v = %d, want %d", d.V, ProtocolVersion)
	}
	return d
}

func TestCallSuccess(t *testing.T) {
	d := decode(t, Call(func() (any, error) {
		return map[string]string{"text": "Olá, ação! 🚀"}, nil
	}))
	if !d.OK || d.Error != nil {
		t.Fatalf("want ok envelope, got %+v", d)
	}
	if got := d.Data["text"]; got != "Olá, ação! 🚀" {
		t.Fatalf("text = %q", got)
	}
}

func TestCallBridgeErrorKeepsCodeAndMessage(t *testing.T) {
	d := decode(t, Call(func() (any, error) {
		return nil, &Error{Code: CodeInvalidArgument, Message: "text is null"}
	}))
	if d.OK || d.Error == nil {
		t.Fatalf("want error envelope, got %+v", d)
	}
	if d.Error.Code != CodeInvalidArgument || d.Error.Message != "text is null" {
		t.Fatalf("error = %+v", d.Error)
	}
}

func TestCallPlainErrorDoesNotLeakMessage(t *testing.T) {
	d := decode(t, Call(func() (any, error) {
		return nil, errors.New("contact +55 11 99999-0000 not found")
	}))
	if d.Error == nil || d.Error.Code != CodeInternal || d.Error.Message != internalMessage {
		t.Fatalf("error = %+v, want generic internal error", d.Error)
	}
}

func TestCallRecoversPanic(t *testing.T) {
	d := decode(t, Call(func() (any, error) {
		panic("secret detail")
	}))
	if d.Error == nil || d.Error.Code != CodeInternal || d.Error.Message != internalMessage {
		t.Fatalf("error = %+v, want generic internal error", d.Error)
	}
}

func TestLiveAllocsCounter(t *testing.T) {
	start := LiveAllocs()
	NoteAlloc()
	NoteAlloc()
	NoteFree()
	if got := LiveAllocs() - start; got != 1 {
		t.Fatalf("live delta = %d, want 1", got)
	}
	NoteFree()
	if got := LiveAllocs(); got != start {
		t.Fatalf("live = %d, want %d", got, start)
	}
}
