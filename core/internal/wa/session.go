// Package wa links the core to a WhatsApp account as a companion device
// . Results reach the app as events.
package wa

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"sync"
	"time"

	_ "github.com/WissCore/go-sqlcipher/v4" // SQLCipher driver for wa.db
	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waCompanionReg"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/store/sqlstore"
	waevents "go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"

	"chatdogaroto/core/internal/bridge"
	"chatdogaroto/core/internal/events"
	"chatdogaroto/core/internal/msgstore"
	"chatdogaroto/core/internal/vault"
)

// DisplayName is how the app shows up in WhatsApp's linked devices list. It
// must look like "Browser (OS)" for code pairing (user choice: discreet).
const DisplayName = "Chrome (Linux)"

// qrWait bounds how long a pairing code request waits for the connection.
const qrWait = 30 * time.Second

func init() {
	store.SetOSInfo("Linux", [3]uint32{0, 1, 0})
	store.DeviceProps.PlatformType = waCompanionReg.DeviceProps_CHROME.Enum()
}

// Session is the single WhatsApp connection of the app.
type Session struct {
	hub *events.Hub

	mu        sync.Mutex
	container *sqlstore.Container
	msgs      *msgstore.Store
	media     *vault.Vault
	client    *whatsmeow.Client
	qrCancel  context.CancelFunc
	qrReady   chan struct{}

	sends  sync.WaitGroup // background sends (tests wait on it)
	syncMu sync.Mutex     // one pass over the deletion queue at a time

	// One backup task at a time, and a backup opened to restore.
	backupMu     sync.Mutex
	backupCancel context.CancelFunc
	restore      *restoring

	// deliverWith replaces whatsmeow for uploads and sends in tests.
	deliverWith func(*whatsmeow.Client) deliverer
}

// NewSession returns a session that reports through hub.
func NewSession(hub *events.Hub) *Session {
	return &Session{hub: hub}
}

func invalidState(message string) error {
	return &bridge.Error{Code: "invalid_state", Message: message}
}

// aliveEvery is how often a sign of life is logged while connected, so the
// report can tell when a dead process stopped.
const aliveEvery = time.Minute

// Start opens the session store at dbPath and connects in the background.
// It reports whether a device is already paired; if not, QR codes follow as
// wa_qr events and PairCode becomes available. When the session is already
// open (for example, started by the Android service), it is reused.
func (s *Session) Start(dbPath, key string) (paired bool, err error) {
	return s.open(dbPath, key, msgstore.SourceApp, false)
}

// Resume connects only when an account is paired, for starts without the
// app on screen: source is "system" or "boot". Without
// an account nothing is left running.
func (s *Session) Resume(dbPath, source, key string) (paired bool, err error) {
	return s.open(dbPath, key, source, true)
}

// Connected reports whether the WhatsApp connection is up right now, and
// the account name then (it may be empty).
func (s *Session) Connected() (connected bool, pushName string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.client == nil || !s.client.IsConnected() || !s.client.IsLoggedIn() {
		return false, ""
	}
	return true, s.client.Store.PushName
}

// ConnectionReport summarizes the connection log.
func (s *Session) ConnectionReport() (msgstore.ConnectionReport, error) {
	s.mu.Lock()
	msgs := s.msgs
	s.mu.Unlock()
	if msgs == nil {
		return msgstore.ConnectionReport{}, invalidState("call cc_wa_start first")
	}
	return msgs.Report(context.Background(), time.Now().UnixMilli())
}

// open opens wa.db, encrypted with key, converting a plain one
// first.
func (s *Session) open(dbPath, key, source string, onlyPaired bool) (paired bool, err error) {
	if err := validateKey(key); err != nil {
		return false, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.client != nil {
		return s.client.Store.ID != nil, nil
	}

	if err := os.MkdirAll(filepath.Dir(dbPath), 0o700); err != nil {
		return false, err
	}
	ctx := context.Background()
	if err := encryptIfPlain(dbPath, key); err != nil {
		return false, err
	}
	// One connection pool for the whatsmeow tables and ours. WAL
	// and a busy timeout let live messages and history imports write safely.
	db, err := sql.Open("sqlite3", dsn(dbPath, key))
	if err != nil {
		return false, err
	}
	if err := db.Ping(); err != nil {
		db.Close()
		if isNotADB(err) {
			return false, unreadable()
		}
		return false, err
	}
	container := sqlstore.NewWithDB(db, "sqlite3", s.logger("db"))
	if err := container.Upgrade(ctx); err != nil {
		container.Close()
		return false, err
	}
	msgs, err := msgstore.Open(ctx, db)
	if err != nil {
		container.Close()
		return false, err
	}
	// Sends cut short when the app stopped are not resumed.
	if err := msgs.FailPending(ctx); err != nil {
		container.Close()
		return false, err
	}
	device, err := container.GetFirstDevice(ctx)
	if err != nil {
		container.Close()
		return false, err
	}
	if onlyPaired && device.ID == nil {
		container.Close()
		return false, nil
	}
	now := time.Now().UnixMilli()
	_ = msgs.LogConnection(ctx, now, msgstore.LogStart, source)

	client := whatsmeow.NewClient(device, s.logger("client"))
	// Messages the sender did not encrypt for this new device yet arrive as
	// "unavailable"; ask the main phone to resend them.
	client.AutomaticMessageRerequestFromPhone = true
	client.AddEventHandler(func(evt any) { s.handle(client, evt) })
	media, err := openVault(ctx, msgs, filepath.Join(filepath.Dir(dbPath), "media"))
	if err != nil {
		container.Close()
		return false, err
	}
	s.container, s.msgs, s.media, s.client = container, msgs, media, client
	s.qrReady = make(chan struct{})
	go s.signsOfLife(client)

	paired = device.ID != nil
	if !paired {
		qrCtx, cancel := context.WithCancel(ctx)
		qrChan, err := client.GetQRChannel(qrCtx)
		if err != nil {
			cancel()
			go shutdown(s.detachLocked())
			return false, err
		}
		s.qrCancel = cancel
		go s.forwardQR(client, qrChan, s.qrReady)
	}

	go func() {
		s.hub.Emit(EventConnecting, nil)
		if err := client.Connect(); err != nil {
			s.hub.Emit(EventError, map[string]any{"code": ErrConnectFailed})
		}
	}()
	return paired, nil
}

// forwardQR relays QR codes to the app and marks the connection ready for
// code pairing at the first one. When whatsmeow runs out of QR codes
// (~2.5 minutes) it disconnects; the session is then closed and the app is
// told, so the next cc_wa_start opens a fresh pairing window.
func (s *Session) forwardQR(client *whatsmeow.Client, qrChan <-chan whatsmeow.QRChannelItem, ready chan struct{}) {
	first := true
	for item := range qrChan {
		switch item.Event {
		case whatsmeow.QRChannelEventCode:
			if first {
				close(ready)
				first = false
			}
			s.hub.Emit(EventQR, map[string]any{"code": item.Code, "timeout_ms": item.Timeout.Milliseconds()})
		case whatsmeow.QRChannelEventError:
			s.hub.Emit(EventError, map[string]any{"code": ErrPairFailed})
		case whatsmeow.QRChannelTimeout.Event:
			s.mu.Lock()
			if s.client != client || client.Store.ID != nil {
				s.mu.Unlock()
				continue
			}
			detached, container, cancel := s.detachLocked()
			s.mu.Unlock()
			go shutdown(detached, container, cancel)
			s.hub.Emit(EventQRExpired, nil)
		}
	}
}

// PairCode asks WhatsApp for an 8-character pairing code for phone. The
// code arrives as a wa_pair_code event; failures as wa_error.
func (s *Session) PairCode(phone string) error {
	digits, err := ValidatePhone(phone)
	if err != nil {
		return err
	}
	s.mu.Lock()
	client, ready := s.client, s.qrReady
	s.mu.Unlock()
	if client == nil {
		return invalidState("call cc_wa_start first")
	}
	if client.Store.ID != nil {
		return invalidState("already paired")
	}

	go func() {
		select {
		case <-ready:
		case <-time.After(qrWait):
			s.hub.Emit(EventError, map[string]any{"code": ErrPairCodeFailed})
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), qrWait)
		defer cancel()
		code, err := client.PairPhone(ctx, digits, true, whatsmeow.PairClientChrome, DisplayName)
		if err != nil {
			s.hub.Emit(EventError, map[string]any{"code": ErrPairCodeFailed})
			return
		}
		s.hub.Emit(EventPairCode, map[string]any{"code": code})
	}()
	return nil
}

// Logout removes this device from the account, deletes the session and
// reports wa_logged_out. Runs in the background.
func (s *Session) Logout() error {
	s.mu.Lock()
	client, msgs, media := s.client, s.msgs, s.media
	s.mu.Unlock()
	if client == nil || client.Store.ID == nil {
		return invalidState("not paired")
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), qrWait)
		defer cancel()
		_ = msgs.Clear(ctx)
		_ = media.Clear()
		if err := client.Logout(ctx); err != nil {
			// The server did not confirm: still drop the local session.
			client.Disconnect()
			_ = client.Store.Delete(ctx)
		}
		s.Stop()
		s.hub.Emit(EventLoggedOut, map[string]any{"reason": "user"})
	}()
	return nil
}

// Stop detaches the session at once and disconnects in the background.
// Safe to call when stopped. It never waits on whatsmeow while holding the
// lock: whatsmeow may be the caller (for example from a LoggedOut event), and
// Disconnect waits for whatsmeow's own goroutines, which would deadlock.
func (s *Session) Stop() {
	s.mu.Lock()
	if s.msgs != nil {
		_ = s.msgs.LogConnection(context.Background(), time.Now().UnixMilli(), msgstore.LogStop, "")
	}
	client, container, cancel := s.detachLocked()
	s.mu.Unlock()
	go shutdown(client, container, cancel)
}

// signsOfLife logs, every few minutes while client is connected, that the
// connection is up. It ends when client is no longer the current one.
func (s *Session) signsOfLife(client *whatsmeow.Client) {
	ticker := time.NewTicker(aliveEvery)
	defer ticker.Stop()
	for range ticker.C {
		msgs := s.storeOf(client)
		if msgs == nil {
			return
		}
		if client.IsConnected() {
			_ = msgs.LogAlive(context.Background(), time.Now().UnixMilli())
		}
	}
}

// detachLocked forgets the current client and store; s.mu must be held.
func (s *Session) detachLocked() (*whatsmeow.Client, *sqlstore.Container, context.CancelFunc) {
	client, container, cancel := s.client, s.container, s.qrCancel
	s.client, s.container, s.msgs, s.media, s.qrCancel = nil, nil, nil, nil, nil
	return client, container, cancel
}

// shutdown closes a detached session. Every argument may be nil.
func shutdown(client *whatsmeow.Client, container *sqlstore.Container, cancel context.CancelFunc) {
	if cancel != nil {
		cancel()
	}
	if client != nil {
		client.Disconnect()
	}
	if container != nil {
		_ = container.Close()
	}
}

// logger returns the whatsmeow logger: silent unless diagnostics are on.
func (s *Session) logger(module string) waLog.Logger {
	return diagLogger{module: module, emit: func(level, msg string) {
		s.hub.Emit(EventLog, map[string]any{"level": level, "msg": msg})
	}}
}

// handle receives whatsmeow events of client (on whatsmeow goroutines).
// Events from a client that was already replaced or stopped are dropped.
func (s *Session) handle(client *whatsmeow.Client, evt any) {
	switch e := evt.(type) {
	case *waevents.Message:
		s.onMessage(client, e)
		return
	case *waevents.HistorySync:
		s.onHistory(client, e)
		return
	case *waevents.Receipt:
		s.onReceipt(client, e)
		return
	case *waevents.DeleteChat:
		s.onChatDeleted(client, e.JID, e.Action.GetMessageRange(), false)
		return
	case *waevents.ClearChat:
		s.onChatDeleted(client, e.JID, e.Action.GetMessageRange(), true)
		return
	case *waevents.DeleteForMe:
		s.onDeleteForMe(client, e)
		return
	}
	t, ok := translate(evt)
	if !ok {
		return
	}
	s.mu.Lock()
	if s.client != client {
		s.mu.Unlock()
		return
	}
	switch t.Type {
	case EventConnected:
		t.Data = map[string]any{"push_name": client.Store.PushName}
		_ = s.msgs.LogConnection(context.Background(), time.Now().UnixMilli(), msgstore.LogConnected, "")
		go s.fillMissingNames(client)
		s.startSync(client) // deletions made while offline
	case EventDisconnected:
		_ = s.msgs.LogConnection(context.Background(), time.Now().UnixMilli(), msgstore.LogDisconnected, "")
	case EventLoggedOut:
		// Removed from the phone: whatsmeow already deleted the stored session.
		// Detach it before telling the app, so a new cc_wa_start starts clean.
		msgs, media := s.msgs, s.media
		detached, container, cancel := s.detachLocked()
		s.mu.Unlock()
		_ = msgs.Clear(context.Background())
		_ = media.Clear()
		// whatsmeow deletes the session concurrently; finish it here so the
		// app's next cc_wa_start cannot load the removed device.
		_ = detached.Store.Delete(context.Background())
		go shutdown(detached, container, cancel)
		s.hub.Emit(t.Type, t.Data)
		return
	}
	s.mu.Unlock()
	s.hub.Emit(t.Type, t.Data)
}
