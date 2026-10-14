package msgstore

import (
	"context"
	"database/sql"
)

// Connection log kinds. The log holds times and kinds only: no
// content, names or numbers.
const (
	LogStart        = "start" // the core opened the session; Source says who
	LogConnected    = "connected"
	LogDisconnected = "disconnected"
	LogStop         = "stop" // closed on purpose
	LogAlive        = "alive"
)

// Who started the core.
const (
	SourceApp    = "app"    // the user opened the app
	SourceSystem = "system" // Android restarted the service
	SourceBoot   = "boot"   // the phone was turned on
)

// Outage causes.
const (
	CauseDrop    = "drop"    // the connection fell
	CauseRestart = "restart" // the process ended and started again
	CauseStop    = "stop"    // closed on purpose
)

// LogEntry is one line of the connection log.
type LogEntry struct {
	TS     int64
	Kind   string
	Source string
}

// Outage is a period without connection.
type Outage struct {
	Start      int64  `json:"start"` // Unix ms
	DurationMS int64  `json:"duration_ms"`
	Cause      string `json:"cause"`
	Source     string `json:"source"`  // who started the core again, for restarts
	Ongoing    bool   `json:"ongoing"` // still offline
}

// ConnectionReport summarizes the log.
type ConnectionReport struct {
	Since       int64          `json:"since"` // first start, Unix ms; 0 = no data
	TotalMS     int64          `json:"total_ms"`
	ConnectedMS int64          `json:"connected_ms"`
	Drops       int            `json:"drops"` // unintended: drops and restarts
	LongestMS   int64          `json:"longest_ms"`
	Starts      map[string]int `json:"starts"` // by source
	Outages     []Outage       `json:"outages"`
}

// maxOutages is how many recent outages a report lists.
const maxOutages = 20

// LogConnection appends an event to the connection log.
func (s *Store) LogConnection(ctx context.Context, ts int64, kind, source string) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO cc_connection_log (ts, kind, source) VALUES (?, ?, ?)`, ts, kind, source)
	return err
}

// LogAlive records that the connection was up at ts. A run of signs of
// life keeps one row: only the latest matters.
func (s *Store) LogAlive(ctx context.Context, ts int64) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var rowid int64
	var kind string
	err = tx.QueryRowContext(ctx,
		`SELECT rowid, kind FROM cc_connection_log ORDER BY rowid DESC LIMIT 1`).Scan(&rowid, &kind)
	switch {
	case err == nil && kind == LogAlive:
		_, err = tx.ExecContext(ctx, `UPDATE cc_connection_log SET ts = ? WHERE rowid = ?`, ts, rowid)
	case err == nil || err == sql.ErrNoRows:
		_, err = tx.ExecContext(ctx,
			`INSERT INTO cc_connection_log (ts, kind) VALUES (?, ?)`, ts, LogAlive)
	}
	if err != nil {
		return err
	}
	return tx.Commit()
}

// Report reads the log and summarizes it up to now.
func (s *Store) Report(ctx context.Context, now int64) (ConnectionReport, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT ts, kind, source FROM cc_connection_log ORDER BY rowid`)
	if err != nil {
		return ConnectionReport{}, err
	}
	defer rows.Close()
	var log []LogEntry
	for rows.Next() {
		var e LogEntry
		if err := rows.Scan(&e.TS, &e.Kind, &e.Source); err != nil {
			return ConnectionReport{}, err
		}
		log = append(log, e)
	}
	if err := rows.Err(); err != nil {
		return ConnectionReport{}, err
	}
	return Summarize(log, now), nil
}

// Summarize computes the report from log entries in the order they were
// written. A process that died leaves no event: its end is estimated by the
// last entry before the next start (a sign of life is written every few
// minutes while connected).
func Summarize(log []LogEntry, now int64) ConnectionReport {
	r := ConnectionReport{Starts: map[string]int{}, Outages: []Outage{}}
	var (
		started   bool  // a start was seen
		online    bool  // connected
		upSince   int64 // when online began
		offOpen   bool  // an outage is open
		off       Outage
		lastSeen  int64 // last entry of the running process
		stopped   bool  // the running process was closed on purpose
		connected bool  // connected at least once since the first start
	)
	closeOutage := func(end int64) {
		off.DurationMS = max(0, end-off.Start)
		r.Outages = append(r.Outages, off)
		if off.Cause != CauseStop {
			r.Drops++
			r.LongestMS = max(r.LongestMS, off.DurationMS)
		}
		offOpen = false
	}
	goOffline := func(at int64, cause string) {
		if online {
			r.ConnectedMS += max(0, at-upSince)
			online = false
		}
		if !offOpen && connected {
			off, offOpen = Outage{Start: at, Cause: cause}, true
		}
	}

	for _, e := range log {
		switch e.Kind {
		case LogStart:
			if !started {
				started, r.Since = true, e.TS
			} else if !stopped {
				// The previous process ended without saying so.
				goOffline(lastSeen, CauseRestart)
			}
			if offOpen && off.Cause == CauseRestart && off.Source == "" {
				off.Source = e.Source
			}
			r.Starts[e.Source]++
			stopped = false
		case LogConnected:
			if offOpen {
				closeOutage(e.TS)
			}
			if !online {
				online, upSince, connected = true, e.TS, true
			}
		case LogDisconnected:
			goOffline(e.TS, CauseDrop)
		case LogStop:
			goOffline(e.TS, CauseStop)
			stopped = true
		}
		lastSeen = e.TS
	}
	if !started {
		return ConnectionReport{Starts: map[string]int{}, Outages: []Outage{}}
	}
	if online {
		r.ConnectedMS += max(0, now-upSince)
	}
	if offOpen {
		off.Ongoing = true
		closeOutage(now)
	}
	r.TotalMS = max(0, now-r.Since)

	// Newest first, and only the latest few.
	for i, j := 0, len(r.Outages)-1; i < j; i, j = i+1, j-1 {
		r.Outages[i], r.Outages[j] = r.Outages[j], r.Outages[i]
	}
	if len(r.Outages) > maxOutages {
		r.Outages = r.Outages[:maxOutages]
	}
	return r
}
