package demo

import (
	"encoding/json"
	"sync"
	"testing"
	"time"

	"chatdogaroto/core/internal/events"
)

type recorder struct {
	mu     sync.Mutex
	events []map[string]any
	doneCh chan struct{}
}

func newRecorder(hub *events.Hub) *recorder {
	r := &recorder{doneCh: make(chan struct{})}
	hub.SetListener(func(b []byte) {
		var e map[string]any
		_ = json.Unmarshal(b, &e)
		r.mu.Lock()
		r.events = append(r.events, e)
		r.mu.Unlock()
		if e["type"] == "ticker_done" {
			close(r.doneCh)
		}
	})
	return r
}

func (r *recorder) ticks() []Tick {
	r.mu.Lock()
	defer r.mu.Unlock()
	var out []Tick
	for _, e := range r.events {
		if e["type"] == "tick" {
			d := e["data"].(map[string]any)
			out = append(out, Tick{Worker: int(d["worker"].(float64)), N: int(d["n"].(float64))})
		}
	}
	return out
}

func TestTickerEmitsInOrderThenDone(t *testing.T) {
	var hub events.Hub
	r := newRecorder(&hub)
	var tk Ticker

	tk.Start(&hub, 20, 1, 0)
	<-r.doneCh

	ticks := r.ticks()
	if len(ticks) != 20 {
		t.Fatalf("got %d ticks, want 20", len(ticks))
	}
	for i, tick := range ticks {
		if tick.N != i+1 || tick.Worker != 1 {
			t.Fatalf("tick %d = %+v", i, tick)
		}
	}
}

func TestTickerWorkersEachInOrder(t *testing.T) {
	var hub events.Hub
	r := newRecorder(&hub)
	var tk Ticker

	tk.Start(&hub, 1000, 4, 0)
	<-r.doneCh

	next := map[int]int{}
	for _, tick := range r.ticks() {
		next[tick.Worker]++
		if tick.N != next[tick.Worker] {
			t.Fatalf("worker %d: got n=%d, want %d", tick.Worker, tick.N, next[tick.Worker])
		}
	}
	for w := 1; w <= 4; w++ {
		if next[w] != 1000 {
			t.Fatalf("worker %d emitted %d ticks, want 1000", w, next[w])
		}
	}
}

func TestStopPreventsFurtherTicks(t *testing.T) {
	var hub events.Hub
	r := newRecorder(&hub)
	var tk Ticker

	tk.Start(&hub, 1000, 1, 5*time.Millisecond)
	time.Sleep(30 * time.Millisecond)
	tk.Stop()
	stoppedAt := len(r.ticks())
	time.Sleep(50 * time.Millisecond)

	if got := len(r.ticks()); got != stoppedAt || got == 1000 {
		t.Fatalf("ticks after stop: %d -> %d", stoppedAt, got)
	}
	select {
	case <-r.doneCh:
		t.Fatal("ticker_done emitted after Stop")
	default:
	}
}
