package wa

import (
	"errors"
	"testing"

	"go.mau.fi/whatsmeow/types/events"

	"chatdogaroto/core/internal/bridge"
)

func TestValidatePhone(t *testing.T) {
	valid := map[string]string{
		"+55 (11) 99999-0000": "5511999990000",
		"5511999990000":       "5511999990000",
		"1 415 555 0100":      "14155550100",
	}
	for in, want := range valid {
		got, err := ValidatePhone(in)
		if err != nil || got != want {
			t.Errorf("ValidatePhone(%q) = %q, %v; want %q", in, got, err, want)
		}
	}

	for _, in := range []string{"", "123", "011999990000", "1234567890123456"} {
		_, err := ValidatePhone(in)
		var bridgeErr *bridge.Error
		if !errors.As(err, &bridgeErr) || bridgeErr.Code != bridge.CodeInvalidArgument {
			t.Errorf("ValidatePhone(%q) err = %v; want invalid_argument", in, err)
		}
	}
}

func TestTranslate(t *testing.T) {
	cases := []struct {
		in       any
		wantType string
		wantCode any
	}{
		{&events.PairSuccess{}, EventPaired, nil},
		{&events.PairError{}, EventError, ErrPairFailed},
		{&events.Connected{}, EventConnected, nil},
		{&events.Disconnected{}, EventDisconnected, nil},
		{&events.StreamReplaced{}, EventDisconnected, nil},
		{&events.LoggedOut{Reason: events.ConnectFailureLoggedOut}, EventLoggedOut, int(events.ConnectFailureLoggedOut)},
		{&events.TemporaryBan{}, EventError, ErrTemporaryBan},
		{&events.ClientOutdated{}, EventError, ErrClientOutdated},
		{&events.ConnectFailure{}, EventError, ErrConnectFailed},
	}
	for _, c := range cases {
		got, ok := translate(c.in)
		if !ok || got.Type != c.wantType {
			t.Errorf("translate(%T) = %+v, %v; want type %s", c.in, got, ok, c.wantType)
			continue
		}
		if c.wantCode != nil && got.Data["code"] != c.wantCode {
			t.Errorf("translate(%T) code = %v; want %v", c.in, got.Data["code"], c.wantCode)
		}
	}

	if _, ok := translate(&events.Message{}); ok {
		t.Error("message events must be ignored until delivery 1.5")
	}
}

func TestRedactMasksNumbers(t *testing.T) {
	in := "Successfully paired 5511999990000@s.whatsapp.net (lid 123456789012345@lid) code 401"
	want := "Successfully paired <num>@s.whatsapp.net (lid <num>@lid) code 401"
	if got := Redact(in); got != want {
		t.Fatalf("Redact = %q, want %q", got, want)
	}
}
