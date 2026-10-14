package wa

import (
	"path/filepath"
	"testing"

	waevents "go.mau.fi/whatsmeow/types/events"

	"chatdogaroto/core/internal/events"
	"chatdogaroto/core/internal/msgstore"
)

func TestResumeWithoutAccountLeavesNothingRunning(t *testing.T) {
	var hub events.Hub
	s := NewSession(&hub)
	paired, err := s.Resume(filepath.Join(t.TempDir(), "wa", "wa.db"), msgstore.SourceBoot, testKey)
	if err != nil || paired {
		t.Fatalf("Resume = %v, %v; want false, nil", paired, err)
	}
	if connected, _ := s.Connected(); s.client != nil || s.msgs != nil || connected {
		t.Fatal("Resume without an account left a session open")
	}
	if _, err := s.ConnectionReport(); errCode(err) != "invalid_state" {
		t.Fatalf("report without session: err = %v", err)
	}
}

func TestConnectionEventsAreLogged(t *testing.T) {
	s, client, _ := offlineSession(t)
	s.msgs.LogConnection(t.Context(), 0, msgstore.LogStart, msgstore.SourceApp)
	s.handle(client, &waevents.Connected{})
	s.handle(client, &waevents.Disconnected{})
	s.handle(client, &waevents.Connected{})

	r, err := s.ConnectionReport()
	if err != nil {
		t.Fatal(err)
	}
	if r.Starts[msgstore.SourceApp] != 1 || r.Drops != 1 || len(r.Outages) != 1 ||
		r.Outages[0].Cause != msgstore.CauseDrop || r.Outages[0].Ongoing {
		t.Fatalf("report = %+v", r)
	}
}

func TestStopIsLoggedAsOnPurpose(t *testing.T) {
	s, client, _ := offlineSession(t)
	msgs := s.msgs
	msgs.LogConnection(t.Context(), 0, msgstore.LogStart, msgstore.SourceApp)
	s.handle(client, &waevents.Connected{})
	s.Stop()

	r, err := msgs.Report(t.Context(), 1<<62)
	if err != nil {
		t.Fatal(err)
	}
	if r.Drops != 0 || len(r.Outages) != 1 || r.Outages[0].Cause != msgstore.CauseStop {
		t.Fatalf("report = %+v", r)
	}
}
