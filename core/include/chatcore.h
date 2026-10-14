// chatcore.h - C API of the Go core (libchatcore), protocol version 1.
//
// This header is the contract between the Go core and the Flutter app:
//  - cmd/chatcore includes it in its cgo preamble, so the C compiler rejects
//    any Go export whose signature drifts from the declarations below;
//  - app/tool/ffigen.dart generates the Dart bindings from it.
//
// Every function that returns `char *` returns a NUL-terminated UTF-8 JSON
// envelope allocated by the core. The caller owns it and must release it with
// cc_free. Envelopes:
//   {"v":1,"ok":true,"data":{...}}
//   {"v":1,"ok":false,"error":{"code":"...","message":"..."}}
//
// cgo cannot export `const` parameters, so input strings are declared as
// `char *`; the core never modifies nor keeps them after the call returns.

#ifndef CHATCORE_H
#define CHATCORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns the core and Go runtime versions: data = {"core": "...", "go": "..."}.
char *cc_version(void);

// Returns `text` unchanged: data = {"text": "..."}.
// A NULL `text` yields the error code "invalid_argument".
char *cc_echo(char *text);

// Releases a string returned by the core. Accepts NULL.
void cc_free(char *p);

// Number of strings returned by the core and not yet released. Used by tests
// to prove that the caller frees everything it receives.
int64_t cc_live_allocs(void);

// Receives one event: a JSON envelope {"v":1,"type":"...","data":{...}}
// allocated by the core. The receiver owns it and must release it with
// cc_free. Called from any thread.
typedef void (*cc_event_fn)(char *event);

// Registers the event listener; NULL unregisters. Unregistering returns only
// after deliveries in progress finished, so the listener can then be freed.
void cc_events_listen(cc_event_fn fn);

// Demo ticker: `workers` concurrent tasks each emit `count` "tick" events
// (data = {"worker": w, "n": i}), `interval_ms` apart, then one "ticker_done"
// event. Starting again stops the previous run. Errors: invalid_argument.
char *cc_ticker_start(int32_t count, int32_t interval_ms, int32_t workers);

// Stops the demo ticker; once it returns, no tick is emitted anymore.
char *cc_ticker_stop(void);

// WhatsApp session. Results arrive as events: wa_connecting,
// wa_qr {code, timeout_ms}, wa_pair_code {code}, wa_paired,
// wa_connected {push_name}, wa_disconnected, wa_logged_out {reason},
// wa_qr_expired (pairing window over; call cc_wa_start again),
// wa_error {code}. No event carries the phone number or the account ID.

// Opens the session stored at db_path (created if missing), encrypted with
// `key` (64 lowercase hex digits), and connects in the background.
// A plain database from earlier versions is encrypted first. If the session is already open (for example, resumed by
// the Android service), it is reused. data = {"paired": bool,
// "connected": bool, "push_name": string} (push_name only when connected).
// Errors: invalid_argument, unreadable (the key does not open db_path; call
// cc_wa_reset and pair again). The key is never logged or echoed.
char *cc_wa_start(char *db_path, char *key);

// Connection without the app on screen: like
// cc_wa_start, but only when an account is paired; otherwise nothing is
// left running. `source` is "system" (Android restarted the service) or
// "boot"; `key` as in cc_wa_start. data = {"paired": bool}.
// Errors: invalid_argument, unreadable.
char *cc_wa_resume(char *db_path, char *source, char *key);

// Deletes the session database files at db_path without opening them,
// after cc_wa_start answered unreadable. Errors: invalid_state (session
// open).
char *cc_wa_reset(char *db_path);

// Summary of the connection log: data = {"since", "total_ms",
// "connected_ms", "drops", "longest_ms", "starts": {source: n},
// "outages": [{"start", "duration_ms", "cause", "source", "ongoing"}]},
// newest outage first. Times are Unix ms; cause is "drop", "restart" or
// "stop". Errors: invalid_state (session not started).
char *cc_connection_report(void);

// Requests an 8-character pairing code for `phone` (international number,
// country code first). The code arrives as a wa_pair_code event.
// Errors: invalid_argument, invalid_state (not started or already paired).
char *cc_wa_pair_code(char *phone);

// Unlinks this device from the account and deletes the session; a
// wa_logged_out event follows. Errors: invalid_state (not paired).
char *cc_wa_logout(void);

// Disconnects and closes the session store (the session stays saved).
char *cc_wa_stop(void);

// Messages. New messages arrive as wa_message events
// (data = the message); the history imported after pairing as wa_history
// {chats, messages}.

// Lists up to `limit` chats, newest first:
// data = {"chats": [{"jid", "name", "last_text", "last_ts"}]}.
// Errors: invalid_state (session not started).
char *cc_chats_list(int32_t limit);

// Lists up to `limit` messages of `chat` older than `before_ts` (Unix ms;
// 0 = newest), oldest first: data = {"messages": [{"chat", "id", "from_me",
// "sender", "sender_name", "kind", "text", "ts", "status"}]}. status is ""
// for received messages, else "sending", "sent", "delivered", "read" or
// "failed".
// Errors: invalid_argument, invalid_state.
char *cc_messages_list(char *chat, int64_t before_ts, int32_t limit);

// Sending. Status changes arrive as wa_message_status events
// {chat, id, status}, also for receipts of messages sent from the phone.
// Nothing is ever resent without a call from the app.

// Stores a text message to `chat` as "sending" and sends it in the
// background: data = {"message": {...}} (as in cc_messages_list). A
// wa_message event with it follows, then wa_message_status "sent" or
// "failed". Errors: invalid_argument (empty or too long text, bad chat),
// invalid_state (not started or not paired).
char *cc_messages_send(char *chat, char *text);

// Sends a "failed" message again with the same ID: data = {"message": {...}}
// with status "sending". Errors: invalid_argument (unknown or not mine),
// invalid_state (not failed, session not started).
char *cc_messages_retry(char *chat, char *id);

// Media. Messages carry "media"
// ("thumb", "remote", "downloaded", "failed", "expired" or ""), "thumb"
// (bool), "file_name", "mime", "size" (bytes), "seconds", "ptt" (voice
// message) and "forwarded". Media are kept encrypted in the vault and
// decrypted only in memory.

// Downloads the photo of a message in the background (only when asked);
// the outcome arrives as wa_media {chat, id, state}. Errors:
// invalid_argument (no photo in that message), invalid_state.
char *cc_media_download(char *chat, char *id);

// Returns a part of a stored photo, `part` "thumb" or "full":
// data = {"data": base64}. Errors: invalid_argument (bad part or not in
// the vault), invalid_state.
char *cc_media_get(char *chat, char *id, char *part);

// Media of any size as bytes, without base64. On
// success *out points to *out_len bytes allocated by the core, which the
// caller releases with cc_bytes_free; data = {}. On error *out stays NULL.
// Errors as cc_media_get.
char *cc_media_read(char *chat, char *id, char *part, uint8_t **out, int64_t *out_len);

// Sends a media to `chat`: `meta` is JSON {"kind": "image",
// "video", "audio" or "document", "caption", "file_name", "mime",
// "seconds", "ptt", "thumb" (base64, a video's preview)}, and `data` the
// `len` bytes, copied before the call returns. Photos are turned upright
// and re-encoded without metadata. The media is kept in the vault.
// data = {"message": {...}} with status "sending"; the outcome arrives as
// wa_message_status. Errors: invalid_argument, too_big (above the app's
// limit), invalid_state (not started or not paired).
char *cc_media_send(char *chat, char *meta, uint8_t *data, int64_t len);

// Forwards message `id` of `chat` to chat `to`, with the "forwarded" mark
//: a media in the vault is uploaded again, otherwise its stored
// download data is reused without downloading it. data = {"message": {...}}
// with status "sending". Errors: invalid_argument (unknown message, nothing
// to forward, bad chat), invalid_state.
char *cc_messages_forward(char *chat, char *id, char *to);

// Deletes a chat here (messages, media, search) and in my WhatsApp;
// without connection WhatsApp gets it when connected. data = {}, and
// a wa_deleted event follows. for_everyone = 1 also deletes for everyone my
// messages of the last 60 h (up to 50, spaced), ending as wa_revoke_done;
// it needs the connection (error offline, nothing deleted). Errors:
// invalid_argument, offline, invalid_state.
char *cc_chats_delete(char *chat, int32_t for_everyone);

// Deletes message `id` of `chat`. for_everyone = 0: for me, here and in my
// WhatsApp (queued without connection); data = {} and wa_deleted follows.
// for_everyone = 1: my message sent less than 60 h ago, deleted for
// everyone in the background, ending as wa_deleted (scope "revoked") or
// wa_delete_failed. Errors: invalid_argument (unknown message, not
// allowed), offline (for everyone without connection), invalid_state.
char *cc_messages_delete(char *chat, char *id, int32_t for_everyone);

// Backup. `fd` is a file descriptor the app opened
// (Android: the file picked by the user); the core takes it and closes it.
//
// Writes the backup to fd in the background. request = {"password",
// "app_copy" (the app.db copy, encrypted with "app_key"), "app_key",
// "app_version", "app_schema", "media", "work_dir"}. data = {}; then
// backup_progress {"done","total"} and backup_done {"bytes"} or
// backup_failed {"code": "failed"|"cancelled"}. Errors: weak_password,
// invalid_argument, busy, invalid_state.
char *cc_backup_export(int32_t fd, char *request);

// Reads and checks the backup in fd in the background. request =
// {"password", "work_dir", "max_app_schema"}. data = {}; then backup_ready
// {"app_copy","app_key","app_schema","media","created_at"} or backup_failed
// {"code": "wrong_password"|"not_a_backup"|"newer_version"|"cancelled"|
// "failed"}. Nothing changes until cc_backup_commit.
char *cc_backup_open(int32_t fd, char *request);

// Replaces the conversations and media with the opened backup, in the
// background; then backup_restored or backup_failed. Errors: invalid_state
// (nothing opened), busy.
char *cc_backup_commit(void);

// Drops an opened backup. data = {}.
char *cc_backup_discard(void);

// Cancels the backup or opening running now. data = {}.
char *cc_backup_cancel(void);

// Releases bytes returned by the core (cc_media_read). Accepts NULL. Counted
// by cc_live_allocs like the strings.
void cc_bytes_free(uint8_t *p);

// The phone number (digits) behind a one-to-one chat, also under a private
// ID (LID) when WhatsApp told it: data = {"phone": "..."}, ""
// when unknown or for groups. Errors: invalid_argument, invalid_state.
char *cc_chat_phone(char *chat);

// The stored chat of a phone number (digits): its own chat, or the one
// under its private ID (LID) when known: data = {"chat": jid},
// "" when there is none. Errors: invalid_argument, invalid_state.
char *cc_chat_for_phone(char *phone);

// Searches stored message texts: accents and case ignored,
// every word as a prefix, all words required; newest first:
// data = {"messages": [...]} as in cc_messages_list. The query is never
// logged. Errors: invalid_state.
char *cc_messages_search(char *query, int32_t limit);

// PIN envelopes: Argon2id + AES-256-GCM. Slow on
// purpose (about a second): call them away from the UI thread. The PIN is
// 6 to 32 digits and is never stored or logged.

// Seals `secret_hex` (64 lowercase hex digits) under `pin`:
// data = {"envelope": base64}. Errors: invalid_argument.
char *cc_pin_seal(char *pin, char *secret_hex);

// Opens an envelope from cc_pin_seal: data = {"secret": hex}.
// Errors: wrong_pin (wrong PIN or altered envelope), invalid_argument.
char *cc_pin_open(char *pin, char *envelope);

// Development builds only: when on, whatsmeow log lines arrive as wa_log
// events {level, msg}, with every run of 6+ digits masked as <num>.
void cc_wa_diagnostics(int32_t on);

#ifdef __cplusplus
}
#endif

#endif  // CHATCORE_H
