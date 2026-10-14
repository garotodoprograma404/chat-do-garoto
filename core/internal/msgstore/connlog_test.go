package msgstore

import (
	"context"
	"testing"
)

const minute = int64(60_000)

func e(ts int64, kind string, source ...string) LogEntry {
	entry := LogEntry{TS: ts, Kind: kind}
	if len(source) > 0 {
		entry.Source = source[0]
	}
	return entry
}

func TestSummarizeEmpty(t *testing.T) {
	r := Summarize(nil, 100)
	if r.Since != 0 || r.TotalMS != 0 || len(r.Outages) != 0 || r.Starts == nil {
		t.Fatalf("empty report = %+v", r)
	}
}

func TestSummarizeDropAndReconnect(t *testing.T) {
	r := Summarize([]LogEntry{
		e(0, LogStart, SourceApp),
		e(1*minute, LogConnected),
		e(60*minute, LogDisconnected),
		e(62*minute, LogConnected),
	}, 120*minute)

	if r.Since != 0 || r.TotalMS != 120*minute {
		t.Fatalf("since/total = %d/%d", r.Since, r.TotalMS)
	}
	if want := 59*minute + 58*minute; r.ConnectedMS != want {
		t.Errorf("connected = %d minute, want %d", r.ConnectedMS/minute, want/minute)
	}
	if r.Drops != 1 || r.LongestMS != 2*minute {
		t.Errorf("drops = %d, longest = %d minute", r.Drops, r.LongestMS/minute)
	}
	want := Outage{Start: 60 * minute, DurationMS: 2 * minute, Cause: CauseDrop}
	if len(r.Outages) != 1 || r.Outages[0] != want {
		t.Errorf("outages = %+v", r.Outages)
	}
	if r.Starts[SourceApp] != 1 {
		t.Errorf("starts = %v", r.Starts)
	}
}

func TestSummarizeProcessDiedBetweenSignsOfLife(t *testing.T) {
	r := Summarize([]LogEntry{
		e(0, LogStart, SourceApp),
		e(1*minute, LogConnected),
		e(30*minute, LogAlive), // last sign before the process died
		e(40*minute, LogStart, SourceSystem),
		e(41*minute, LogConnected),
	}, 50*minute)

	want := Outage{Start: 30 * minute, DurationMS: 11 * minute, Cause: CauseRestart, Source: SourceSystem}
	if len(r.Outages) != 1 || r.Outages[0] != want {
		t.Fatalf("outages = %+v, want %+v", r.Outages, want)
	}
	if r.Drops != 1 || r.ConnectedMS != 29*minute+9*minute {
		t.Errorf("drops = %d, connected = %d minute", r.Drops, r.ConnectedMS/minute)
	}
	if r.Starts[SourceSystem] != 1 || r.Starts[SourceApp] != 1 {
		t.Errorf("starts = %v", r.Starts)
	}
}

func TestSummarizeStopIsNotADrop(t *testing.T) {
	r := Summarize([]LogEntry{
		e(0, LogStart, SourceApp),
		e(1*minute, LogConnected),
		e(10*minute, LogStop),
		e(20*minute, LogStart, SourceBoot),
		e(21*minute, LogConnected),
	}, 30*minute)

	if r.Drops != 0 || r.LongestMS != 0 {
		t.Errorf("drops = %d, longest = %d", r.Drops, r.LongestMS)
	}
	if len(r.Outages) != 1 || r.Outages[0].Cause != CauseStop || r.Outages[0].DurationMS != 11*minute {
		t.Errorf("outages = %+v", r.Outages)
	}
}

func TestSummarizeOngoingOutageNewestFirst(t *testing.T) {
	r := Summarize([]LogEntry{
		e(0, LogStart, SourceApp),
		e(1*minute, LogConnected),
		e(5*minute, LogDisconnected),
		e(6*minute, LogConnected),
		e(10*minute, LogDisconnected),
	}, 25*minute)

	if len(r.Outages) != 2 || !r.Outages[0].Ongoing || r.Outages[0].DurationMS != 15*minute {
		t.Fatalf("outages = %+v", r.Outages)
	}
	if r.Outages[1].Start != 5*minute || r.Drops != 2 || r.LongestMS != 15*minute {
		t.Errorf("report = %+v", r)
	}
}

func TestSummarizeBeforeFirstConnectionIsNotAnOutage(t *testing.T) {
	r := Summarize([]LogEntry{
		e(0, LogStart, SourceApp),
		e(5*minute, LogStart, SourceSystem), // died before connecting
		e(6*minute, LogConnected),
	}, 10*minute)
	if len(r.Outages) != 0 || r.ConnectedMS != 4*minute {
		t.Fatalf("report = %+v", r)
	}
}

func TestLogIsStoredAndClearedWithTheMessages(t *testing.T) {
	s, ctx := open(t), context.Background()
	s.LogConnection(ctx, 0, LogStart, SourceApp)
	s.LogConnection(ctx, 1*minute, LogConnected, "")
	s.LogAlive(ctx, 5*minute)
	s.LogAlive(ctx, 10*minute) // replaces the previous sign of life

	var rows int
	s.db.QueryRow(`SELECT COUNT(*) FROM cc_connection_log`).Scan(&rows)
	if rows != 3 {
		t.Fatalf("rows = %d, want 3 (signs of life collapse)", rows)
	}
	r, err := s.Report(ctx, 20*minute)
	if err != nil || r.ConnectedMS != 19*minute {
		t.Fatalf("report = %+v, %v", r, err)
	}

	if err := s.Clear(ctx); err != nil {
		t.Fatal(err)
	}
	if r, _ := s.Report(ctx, 30*minute); r.Since != 0 {
		t.Fatalf("log not cleared: %+v", r)
	}
}
