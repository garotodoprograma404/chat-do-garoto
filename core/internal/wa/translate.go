package wa

import (
	"strings"

	"go.mau.fi/whatsmeow/types/events"

	"chatdogaroto/core/internal/bridge"
)

// Event types sent to the app.
const (
	EventConnecting   = "wa_connecting"
	EventQR           = "wa_qr"
	EventPairCode     = "wa_pair_code"
	EventPaired       = "wa_paired"
	EventConnected    = "wa_connected"
	EventDisconnected = "wa_disconnected"
	EventLoggedOut    = "wa_logged_out"
	EventQRExpired    = "wa_qr_expired"
	EventError        = "wa_error"
	EventLog          = "wa_log" // diagnostics only, see SetDiagnostics
)

// Error codes sent in wa_error events.
const (
	ErrConnectFailed  = "connect_failed"
	ErrPairFailed     = "pair_failed"
	ErrPairCodeFailed = "pair_code_failed"
	ErrTemporaryBan   = "temporary_ban"
	ErrClientOutdated = "client_outdated"
)

// translated is an app event derived from a whatsmeow event.
type translated struct {
	Type string
	Data map[string]any
}

// translate maps a whatsmeow event to an app event. It never copies phone
// numbers, account IDs or message content. ok is false for events the app
// does not need yet.
func translate(evt any) (t translated, ok bool) {
	switch e := evt.(type) {
	case *events.PairSuccess:
		return translated{Type: EventPaired}, true
	case *events.PairError:
		return errorEvent(ErrPairFailed), true
	case *events.Connected:
		return translated{Type: EventConnected}, true
	case *events.Disconnected:
		return translated{Type: EventDisconnected}, true
	case *events.StreamReplaced:
		return translated{Type: EventDisconnected, Data: map[string]any{"reason": "replaced"}}, true
	case *events.LoggedOut:
		return translated{Type: EventLoggedOut, Data: map[string]any{"reason": "removed_by_phone", "code": int(e.Reason)}}, true
	case *events.TemporaryBan:
		return errorEvent(ErrTemporaryBan), true
	case *events.ClientOutdated:
		return errorEvent(ErrClientOutdated), true
	case *events.ConnectFailure:
		return errorEvent(ErrConnectFailed), true
	default:
		return translated{}, false
	}
}

func errorEvent(code string) translated {
	return translated{Type: EventError, Data: map[string]any{"code": code}}
}

// ValidatePhone returns the digits of an international phone number
// (country and area code, no leading 0), or an invalid_argument error. The
// number itself never goes into the error message.
func ValidatePhone(phone string) (string, error) {
	var digits strings.Builder
	for _, r := range phone {
		if r >= '0' && r <= '9' {
			digits.WriteRune(r)
		}
	}
	d := digits.String()
	switch {
	case len(d) < 7:
		return "", &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "phone number too short"}
	case len(d) > 15:
		return "", &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "phone number too long"}
	case strings.HasPrefix(d, "0"):
		return "", &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "phone number must start with the country code"}
	}
	return d, nil
}
