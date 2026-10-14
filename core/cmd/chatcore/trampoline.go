package main

// The preamble of a file with //export may only hold declarations, so the C
// helper that calls the listener's function pointer lives here.

/*
#include "chatcore.h"

static inline void cc_call_event_fn(cc_event_fn fn, char *event) { fn(event); }
*/
import "C"

// callListener hands an event to the C listener. The listener owns event.
func callListener(fn C.cc_event_fn, event *C.char) {
	C.cc_call_event_fn(fn, event)
}
