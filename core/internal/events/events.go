// Package events delivers events from the core to the app through a single
// registered listener.
package events

import (
	"encoding/json"
	"sync"

	"chatdogaroto/core/internal/bridge"
)

// Listener receives one encoded event. It must not block.
type Listener func(event []byte)

// Hub holds the registered listener. The zero value has no listener.
type Hub struct {
	mu       sync.RWMutex
	listener Listener
}

// SetListener registers l, or unregisters with nil. It returns only after
// deliveries in progress finished, so after SetListener(nil) the previous
// listener is never called again.
func (h *Hub) SetListener(l Listener) {
	h.mu.Lock()
	h.listener = l
	h.mu.Unlock()
}

// Emit delivers an event of the given type and reports whether a listener
// received it. Safe to call from any goroutine.
func (h *Hub) Emit(eventType string, data any) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	if h.listener == nil {
		return false
	}
	h.listener(Encode(eventType, data))
	return true
}

type envelope struct {
	V    int    `json:"v"`
	Type string `json:"type"`
	Data any    `json:"data,omitempty"`
}

// Encode builds the event envelope {"v":1,"type":...,"data":...}.
func Encode(eventType string, data any) []byte {
	b, err := json.Marshal(envelope{V: bridge.ProtocolVersion, Type: eventType, Data: data})
	if err != nil {
		b, _ = json.Marshal(envelope{V: bridge.ProtocolVersion, Type: "encoding_error"})
	}
	return b
}
