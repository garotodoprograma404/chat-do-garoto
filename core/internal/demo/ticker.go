// Package demo holds throwaway features used to exercise the bridge during
// the prototype phase. It goes away once real WhatsApp events exist.
package demo

import (
	"context"
	"sync"
	"time"

	"chatdogaroto/core/internal/events"
)

// Ticker emits numbered "tick" events from concurrent workers.
type Ticker struct {
	mu     sync.Mutex
	cancel context.CancelFunc
	done   chan struct{}
}

// Tick is the data of a "tick" event.
type Tick struct {
	Worker int `json:"worker"`
	N      int `json:"n"`
}

// Start stops any previous run, then starts `workers` goroutines that each
// emit `count` ticks numbered 1..count, `interval` apart. When every worker
// finished without being stopped, one "ticker_done" event follows.
func (t *Ticker) Start(hub *events.Hub, count, workers int, interval time.Duration) {
	t.Stop()

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	t.mu.Lock()
	t.cancel, t.done = cancel, done
	t.mu.Unlock()

	go func() {
		defer close(done)
		var wg sync.WaitGroup
		for w := 1; w <= workers; w++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for n := 1; n <= count; n++ {
					if !wait(ctx, interval) {
						return
					}
					hub.Emit("tick", Tick{Worker: w, N: n})
				}
			}()
		}
		wg.Wait()
		if ctx.Err() == nil {
			hub.Emit("ticker_done", map[string]int{"count": count, "workers": workers})
		}
	}()
}

// Stop cancels the current run and returns once no tick can be emitted
// anymore. Safe to call when nothing is running.
func (t *Ticker) Stop() {
	t.mu.Lock()
	cancel, done := t.cancel, t.done
	t.cancel, t.done = nil, nil
	t.mu.Unlock()
	if cancel != nil {
		cancel()
		<-done
	}
}

// wait sleeps for d and reports whether the run is still active.
func wait(ctx context.Context, d time.Duration) bool {
	if d <= 0 {
		return ctx.Err() == nil
	}
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
