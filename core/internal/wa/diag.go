package wa

import (
	"fmt"
	"regexp"
	"sync/atomic"

	waLog "go.mau.fi/whatsmeow/util/log"
)

// Diagnostics are off by default. The debug build of the app can turn them
// on to see why a connection fails; every run of 6+ digits (phone numbers,
// account IDs) is masked before anything leaves this package.
var diagnostics atomic.Bool

// SetDiagnostics turns whatsmeow diagnostics (wa_log events) on or off.
func SetDiagnostics(on bool) { diagnostics.Store(on) }

var digits = regexp.MustCompile(`\d{6,}`)

// Redact masks phone numbers and account IDs in a diagnostic line.
func Redact(s string) string { return digits.ReplaceAllString(s, "<num>") }

// diagLogger forwards whatsmeow log lines as wa_log events while
// diagnostics are on. Debug lines are dropped (too noisy).
type diagLogger struct {
	module string
	emit   func(level, msg string)
}

func (l diagLogger) log(level, format string, args ...any) {
	if !diagnostics.Load() {
		return
	}
	l.emit(level, Redact(l.module+": "+fmt.Sprintf(format, args...)))
}

func (l diagLogger) Errorf(format string, args ...any) { l.log("error", format, args...) }
func (l diagLogger) Warnf(format string, args ...any)  { l.log("warn", format, args...) }
func (l diagLogger) Infof(format string, args ...any)  { l.log("info", format, args...) }
func (l diagLogger) Debugf(string, ...any)             {}
func (l diagLogger) Sub(module string) waLog.Logger {
	return diagLogger{module: l.module + "/" + module, emit: l.emit}
}
