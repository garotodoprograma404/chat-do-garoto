package events

import (
	"encoding/json"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestEmitWithoutListenerIsDropped(t *testing.T) {
	var h Hub
	if h.Emit("tick", nil) {
		t.Fatal("Emit reported delivery without a listener")
	}
}

func TestEmitEncodesEnvelope(t *testing.T) {
	var h Hub
	var got []byte
	h.SetListener(func(e []byte) { got = e })

	if !h.Emit("tick", map[string]int{"n": 7}) {
		t.Fatal("Emit reported no delivery")
	}
	var e struct {
		V    int            `json:"v"`
		Type string         `json:"type"`
		Data map[string]int `json:"data"`
	}
	if err := json.Unmarshal(got, &e); err != nil {
		t.Fatalf("invalid event %q: %v", got, err)
	}
	if e.V != 1 || e.Type != "tick" || e.Data["n"] != 7 {
		t.Fatalf("event = %+v", e)
	}
}

func TestConcurrentEmitsAllDelivered(t *testing.T) {
	var h Hub
	var delivered atomic.Int64
	h.SetListener(func([]byte) { delivered.Add(1) })

	var wg sync.WaitGroup
	for w := 0; w < 8; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 1000; i++ {
				h.Emit("tick", i)
			}
		}()
	}
	wg.Wait()
	if got := delivered.Load(); got != 8000 {
		t.Fatalf("delivered %d events, want 8000", got)
	}
}

func TestUnregisterWaitsForDeliveryInProgress(t *testing.T) {
	var h Hub
	inside := make(chan struct{})
	release := make(chan struct{})
	var calledAfterUnregister atomic.Bool
	var unregistered atomic.Bool

	h.SetListener(func([]byte) {
		if unregistered.Load() {
			calledAfterUnregister.Store(true)
		}
		close(inside)
		<-release
	})
	go h.Emit("tick", nil)
	<-inside

	done := make(chan struct{})
	go func() {
		h.SetListener(nil)
		unregistered.Store(true)
		close(done)
	}()
	select {
	case <-done:
		t.Fatal("SetListener(nil) returned while a delivery was in progress")
	case <-time.After(50 * time.Millisecond):
	}
	close(release)
	<-done

	if h.Emit("tick", nil) || calledAfterUnregister.Load() {
		t.Fatal("listener was called after unregistering")
	}
}
