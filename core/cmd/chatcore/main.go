// Command chatcore is the C API of the Go core. It is built with
// -buildmode=c-shared into libchatcore and loaded by the Flutter app through
// dart:ffi.
//
// Keep this package thin: convert types and delegate to internal packages.
// Every exported function goes through bridge.Call, so no panic crosses the
// bridge, and every returned string is released by the app with cc_free.
package main

/*
#cgo CFLAGS: -I${SRCDIR}/../../include
#include <stdlib.h>
#include "chatcore.h"
*/
import "C"

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"runtime"
	"syscall"
	"time"
	"unsafe"

	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/demo"
	"chatdogaroto/core/internal/events"
	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/pinseal"
	"chatdogaroto/core/internal/wa"
)

var (
	hub     events.Hub
	ticker  demo.Ticker
	session = wa.NewSession(&hub)
)

// cc_version returns the core and Go versions. The caller frees the result
// with cc_free.
//
//export cc_version
func cc_version() *C.char {
	return toC(bridge.Call(func() (any, error) {
		return map[string]string{"core": bridge.CoreVersion, "go": runtime.Version()}, nil
	}))
}

// cc_echo returns text unchanged. text is borrowed for the duration of the
// call. The caller frees the result with cc_free.
//
//export cc_echo
func cc_echo(text *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if text == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "text is null"}
		}
		return map[string]string{"text": C.GoString(text)}, nil
	}))
}

// cc_free releases a string returned by the core. It accepts NULL.
//
//export cc_free
func cc_free(p *C.char) {
	if p == nil {
		return
	}
	C.free(unsafe.Pointer(p))
	bridge.NoteFree()
}

// cc_live_allocs returns how many strings returned by the core were not
// released yet.
//
//export cc_live_allocs
func cc_live_allocs() C.int64_t {
	return C.int64_t(bridge.LiveAllocs())
}

// cc_events_listen registers the app's event listener, or unregisters it with
// NULL. Each event is handed over as a string the listener frees with cc_free.
//
//export cc_events_listen
func cc_events_listen(fn C.cc_event_fn) {
	if fn == nil {
		hub.SetListener(nil)
		return
	}
	hub.SetListener(func(event []byte) { callListener(fn, toC(event)) })
}

// cc_ticker_start starts the demo ticker. The caller frees the result with
// cc_free.
//
//export cc_ticker_start
func cc_ticker_start(count, intervalMS, workers C.int32_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if count < 1 || count > 1_000_000 || intervalMS < 0 || intervalMS > 60_000 || workers < 1 || workers > 64 {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "count 1..1000000, interval_ms 0..60000, workers 1..64"}
		}
		ticker.Start(&hub, int(count), int(workers), time.Duration(intervalMS)*time.Millisecond)
		return nil, nil
	}))
}

// cc_ticker_stop stops the demo ticker; no tick is emitted after it returns.
// The caller frees the result with cc_free.
//
//export cc_ticker_stop
func cc_ticker_stop() *C.char {
	return toC(bridge.Call(func() (any, error) {
		ticker.Stop()
		return nil, nil
	}))
}

// cc_wa_start opens the WhatsApp session and connects in the background.
// The caller frees the result with cc_free.
//
//export cc_wa_start
func cc_wa_start(dbPath, key *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if dbPath == nil || C.GoString(dbPath) == "" || key == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "db_path or key is empty"}
		}
		paired, err := session.Start(C.GoString(dbPath), C.GoString(key))
		if err != nil {
			return nil, err
		}
		connected, pushName := session.Connected()
		return map[string]any{"paired": paired, "connected": connected, "push_name": pushName}, nil
	}))
}

// cc_wa_resume connects a paired account without the app on screen (called
// from the Android service through JNI). The caller frees the result with
// cc_free.
//
//export cc_wa_resume
func cc_wa_resume(dbPath, source, key *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if dbPath == nil || C.GoString(dbPath) == "" || source == nil || key == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "db_path, source or key is empty"}
		}
		src := C.GoString(source)
		if src != msgstore.SourceSystem && src != msgstore.SourceBoot {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "unknown source"}
		}
		paired, err := session.Resume(C.GoString(dbPath), src, C.GoString(key))
		if err != nil {
			return nil, err
		}
		return map[string]bool{"paired": paired}, nil
	}))
}

// cc_wa_reset deletes an unreadable session database. The caller frees the
// result with cc_free.
//
//export cc_wa_reset
func cc_wa_reset(dbPath *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if dbPath == nil || C.GoString(dbPath) == "" {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "db_path is empty"}
		}
		return nil, session.Reset(C.GoString(dbPath))
	}))
}

// cc_connection_report summarizes the connection log. The caller frees the
// result with cc_free.
//
//export cc_connection_report
func cc_connection_report() *C.char {
	return toC(bridge.Call(func() (any, error) {
		return session.ConnectionReport()
	}))
}

// cc_wa_pair_code requests a pairing code; it arrives as an event. The
// caller frees the result with cc_free.
//
//export cc_wa_pair_code
func cc_wa_pair_code(phone *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if phone == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "phone is null"}
		}
		return nil, session.PairCode(C.GoString(phone))
	}))
}

// cc_wa_logout unlinks the device and deletes the session. The caller frees
// the result with cc_free.
//
//export cc_wa_logout
func cc_wa_logout() *C.char {
	return toC(bridge.Call(func() (any, error) {
		return nil, session.Logout()
	}))
}

// cc_wa_stop disconnects, keeping the session saved. The caller frees the
// result with cc_free.
//
//export cc_wa_stop
func cc_wa_stop() *C.char {
	return toC(bridge.Call(func() (any, error) {
		session.Stop()
		return nil, nil
	}))
}

// cc_chats_list lists stored chats, newest first. The caller frees the
// result with cc_free.
//
//export cc_chats_list
func cc_chats_list(limit C.int32_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		chats, err := session.ListChats(clampLimit(limit))
		if err != nil {
			return nil, err
		}
		return map[string]any{"chats": chats}, nil
	}))
}

// cc_messages_list lists a page of a chat's messages, oldest first. The
// caller frees the result with cc_free.
//
//export cc_messages_list
func cc_messages_list(chat *C.char, beforeTS C.int64_t, limit C.int32_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || C.GoString(chat) == "" {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat is empty"}
		}
		msgs, err := session.ListMessages(C.GoString(chat), int64(beforeTS), clampLimit(limit))
		if err != nil {
			return nil, err
		}
		return map[string]any{"messages": msgs}, nil
	}))
}

// cc_messages_send stores and sends a text message. The caller frees the
// result with cc_free.
//
//export cc_messages_send
func cc_messages_send(chat, text *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || text == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat or text is null"}
		}
		m, err := session.SendText(C.GoString(chat), C.GoString(text))
		if err != nil {
			return nil, err
		}
		return map[string]any{"message": m}, nil
	}))
}

// cc_messages_retry sends a failed message again. The caller frees the
// result with cc_free.
//
//export cc_messages_retry
func cc_messages_retry(chat, id *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || id == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat or id is null"}
		}
		m, err := session.Retry(C.GoString(chat), C.GoString(id))
		if err != nil {
			return nil, err
		}
		return map[string]any{"message": m}, nil
	}))
}

// cc_media_download downloads a photo into the vault. The caller frees the
// result with cc_free.
//
//export cc_media_download
func cc_media_download(chat, id *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || id == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat or id is null"}
		}
		return nil, session.DownloadMedia(C.GoString(chat), C.GoString(id))
	}))
}

// cc_media_get returns a part of a stored photo. The caller frees the result
// with cc_free.
//
//export cc_media_get
func cc_media_get(chat, id, part *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || id == nil || part == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat, id or part is null"}
		}
		data, err := session.Media(C.GoString(chat), C.GoString(id), C.GoString(part))
		if err != nil {
			return nil, err
		}
		defer clear(data)
		return map[string]string{"data": base64.StdEncoding.EncodeToString(data)}, nil
	}))
}

// cc_media_read hands a stored media part over as bytes. The
// caller frees the result with cc_free and *out with cc_bytes_free.
//
//export cc_media_read
func cc_media_read(chat, id, part *C.char, out **C.uint8_t, outLen *C.int64_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || id == nil || part == nil || out == nil || outLen == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "an argument is null"}
		}
		*out, *outLen = nil, 0
		data, err := session.Media(C.GoString(chat), C.GoString(id), C.GoString(part))
		if err != nil {
			return nil, err
		}
		defer clear(data)
		p := C.malloc(C.size_t(max(len(data), 1)))
		copy(unsafe.Slice((*byte)(p), len(data)), data)
		bridge.NoteAlloc()
		*out, *outLen = (*C.uint8_t)(p), C.int64_t(len(data))
		return map[string]any{}, nil
	}))
}

// cc_media_send sends a media. The caller frees the result with cc_free.
//
//export cc_media_send
func cc_media_send(chat, meta *C.char, data *C.uint8_t, length C.int64_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || meta == nil || data == nil || length <= 0 {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat, meta or data is missing"}
		}
		var m wa.MediaMeta
		if err := json.Unmarshal([]byte(C.GoString(meta)), &m); err != nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "meta is not valid JSON"}
		}
		if length > 100<<20 {
			return nil, &bridge.Error{Code: wa.CodeTooBig, Message: "media is too big"}
		}
		bytes := C.GoBytes(unsafe.Pointer(data), C.int(length))
		defer clear(bytes)
		msg, err := session.SendMedia(C.GoString(chat), m, bytes)
		if err != nil {
			return nil, err
		}
		return map[string]any{"message": msg}, nil
	}))
}

// cc_messages_forward forwards a message. The caller frees the result
// with cc_free.
//
//export cc_messages_forward
func cc_messages_forward(chat, id, to *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || id == nil || to == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat, id or to is null"}
		}
		msg, err := session.Forward(C.GoString(chat), C.GoString(id), C.GoString(to))
		if err != nil {
			return nil, err
		}
		return map[string]any{"message": msg}, nil
	}))
}

// cc_chats_delete deletes a chat here and in my WhatsApp. The caller frees
// the result with cc_free.
//
//export cc_chats_delete
func cc_chats_delete(chat *C.char, forEveryone C.int32_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat is null"}
		}
		return map[string]any{}, session.DeleteChat(C.GoString(chat), forEveryone != 0)
	}))
}

// cc_messages_delete deletes a message for me or for everyone. The caller
// frees the result with cc_free.
//
//export cc_messages_delete
func cc_messages_delete(chat, id *C.char, forEveryone C.int32_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil || id == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat or id is null"}
		}
		if forEveryone != 0 {
			return map[string]any{}, session.RevokeForEveryone(C.GoString(chat), C.GoString(id))
		}
		return map[string]any{}, session.DeleteForMe(C.GoString(chat), C.GoString(id))
	}))
}

// cc_backup_export writes a backup to fd. The caller frees the result.
//
//export cc_backup_export
func cc_backup_export(fd C.int32_t, request *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		var req wa.ExportRequest
		if request == nil || json.Unmarshal([]byte(C.GoString(request)), &req) != nil {
			if fd >= 0 {
				syscall.Close(int(fd))
			}
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "invalid request"}
		}
		if fd < 0 {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "invalid file"}
		}
		return map[string]any{}, session.BackupExport(int(fd), req)
	}))
}

// cc_backup_open reads and checks a backup in fd. The caller frees the
// result.
//
//export cc_backup_open
func cc_backup_open(fd C.int32_t, request *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		var req wa.OpenRequest
		if request == nil || json.Unmarshal([]byte(C.GoString(request)), &req) != nil {
			if fd >= 0 {
				syscall.Close(int(fd))
			}
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "invalid request"}
		}
		if fd < 0 {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "invalid file"}
		}
		return map[string]any{}, session.BackupOpen(int(fd), req)
	}))
}

// cc_backup_commit restores the opened backup. The caller frees the result.
//
//export cc_backup_commit
func cc_backup_commit() *C.char {
	return toC(bridge.Call(func() (any, error) {
		return map[string]any{}, session.BackupCommit()
	}))
}

// cc_backup_discard drops an opened backup. The caller frees the result.
//
//export cc_backup_discard
func cc_backup_discard() *C.char {
	return toC(bridge.Call(func() (any, error) {
		session.BackupDiscard()
		return map[string]any{}, nil
	}))
}

// cc_backup_cancel cancels the running backup task. The caller frees the
// result.
//
//export cc_backup_cancel
func cc_backup_cancel() *C.char {
	return toC(bridge.Call(func() (any, error) {
		session.BackupCancel()
		return map[string]any{}, nil
	}))
}

// cc_bytes_free releases bytes returned by the core.
//
//export cc_bytes_free
func cc_bytes_free(p *C.uint8_t) {
	if p == nil {
		return
	}
	bridge.NoteFree()
	C.free(unsafe.Pointer(p))
}

// cc_chat_phone returns the phone behind a chat. The caller frees the
// result with cc_free.
//
//export cc_chat_phone
func cc_chat_phone(chat *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if chat == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "chat is null"}
		}
		phone, err := session.PhoneOf(C.GoString(chat))
		if err != nil {
			return nil, err
		}
		return map[string]string{"phone": phone}, nil
	}))
}

// cc_chat_for_phone finds the chat of a phone. The caller frees the result
// with cc_free.
//
//export cc_chat_for_phone
func cc_chat_for_phone(phone *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if phone == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "phone is null"}
		}
		chat, err := session.ChatForPhone(C.GoString(phone))
		if err != nil {
			return nil, err
		}
		return map[string]string{"chat": chat}, nil
	}))
}

// cc_messages_search searches message texts. The caller frees the result
// with cc_free.
//
//export cc_messages_search
func cc_messages_search(query *C.char, limit C.int32_t) *C.char {
	return toC(bridge.Call(func() (any, error) {
		if query == nil {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "query is null"}
		}
		msgs, err := session.SearchMessages(C.GoString(query), clampLimit(limit))
		if err != nil {
			return nil, err
		}
		return map[string]any{"messages": msgs}, nil
	}))
}

// cc_pin_seal seals a secret under a PIN. The caller frees the result with
// cc_free.
//
//export cc_pin_seal
func cc_pin_seal(pin, secretHex *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		p, secret, err := pinArgs(pin, secretHex)
		if err != nil {
			return nil, err
		}
		decoded, err := hex.DecodeString(secret)
		if err != nil || len(decoded) != 32 || !isLowerHex(secret) {
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "secret must be 64 lowercase hex digits"}
		}
		envelope, err := pinseal.Seal(p, decoded)
		clear(p)
		clear(decoded)
		if err != nil {
			return nil, err
		}
		return map[string]string{"envelope": envelope}, nil
	}))
}

// cc_pin_open opens a PIN envelope. The caller frees the result with
// cc_free.
//
//export cc_pin_open
func cc_pin_open(pin, envelope *C.char) *C.char {
	return toC(bridge.Call(func() (any, error) {
		p, env, err := pinArgs(pin, envelope)
		if err != nil {
			return nil, err
		}
		secret, err := pinseal.Open(p, env)
		clear(p)
		switch {
		case errors.Is(err, pinseal.ErrWrongPIN):
			return nil, &bridge.Error{Code: "wrong_pin", Message: "the PIN does not open the envelope"}
		case errors.Is(err, pinseal.ErrMalformed):
			return nil, &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "malformed envelope"}
		case err != nil:
			return nil, err
		}
		defer clear(secret)
		return map[string]string{"secret": hex.EncodeToString(secret)}, nil
	}))
}

// pinArgs checks a PIN (6 to 32 digits) and a second, non-empty argument.
// Errors never echo the PIN.
func pinArgs(pin, other *C.char) ([]byte, string, error) {
	if pin == nil || other == nil || C.GoString(other) == "" {
		return nil, "", &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "pin or argument is empty"}
	}
	p := []byte(C.GoString(pin))
	if len(p) < 6 || len(p) > 32 {
		return nil, "", &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "pin must be 6 to 32 digits"}
	}
	for _, c := range p {
		if c < '0' || c > '9' {
			return nil, "", &bridge.Error{Code: bridge.CodeInvalidArgument, Message: "pin must be 6 to 32 digits"}
		}
	}
	return p, C.GoString(other), nil
}

func isLowerHex(s string) bool {
	for _, c := range s {
		if !('0' <= c && c <= '9' || 'a' <= c && c <= 'f') {
			return false
		}
	}
	return true
}

// clampLimit keeps page sizes between 1 and 500.
func clampLimit(limit C.int32_t) int {
	return int(max(1, min(limit, 500)))
}

// cc_wa_diagnostics turns redacted whatsmeow diagnostics on or off.
//
//export cc_wa_diagnostics
func cc_wa_diagnostics(on C.int32_t) {
	wa.SetDiagnostics(on != 0)
}

// toC copies an envelope into C memory owned by the caller.
func toC(b []byte) *C.char {
	bridge.NoteAlloc()
	return C.CString(string(b))
}

func main() {}
