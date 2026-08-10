package connect

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"
)

func testHub() *Hub {
	return New(slog.New(slog.NewTextHandler(io.Discard, nil)), nil)
}

func meta(id string) DeviceMeta {
	return DeviceMeta{ID: id, Name: id, Type: "web"}
}

// register + subscribe, returning the event channel with the hello drained.
func join(t *testing.T, h *Hub, userID, deviceID string) <-chan Event {
	t.Helper()
	if _, err := h.Register(userID, meta(deviceID)); err != nil {
		t.Fatalf("Register(%s): %v", deviceID, err)
	}
	ch, cancel, err := h.Subscribe(userID, deviceID)
	if err != nil {
		t.Fatalf("Subscribe(%s): %v", deviceID, err)
	}
	t.Cleanup(cancel)
	if ev := recv(t, ch); ev.Name != EventHello {
		t.Fatalf("first event = %q, want hello", ev.Name)
	}
	return ch
}

func recv(t *testing.T, ch <-chan Event) Event {
	t.Helper()
	select {
	case ev, ok := <-ch:
		if !ok {
			t.Fatal("channel closed")
		}
		return ev
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for event")
		return Event{}
	}
}

// waitFor drains until an event of the given name arrives.
func waitFor(t *testing.T, ch <-chan Event, name string) Event {
	t.Helper()
	for i := 0; i < 10; i++ {
		ev := recv(t, ch)
		if ev.Name == name {
			return ev
		}
	}
	t.Fatalf("no %q event", name)
	return Event{}
}

func TestDevicesAreScopedToTheirUser(t *testing.T) {
	h := testHub()
	if _, err := h.Register("u1", meta("d1")); err != nil {
		t.Fatal(err)
	}
	if _, err := h.Register("u2", meta("d2")); err != nil {
		t.Fatal(err)
	}

	d1 := h.Devices("u1")
	if len(d1) != 1 || d1[0].ID != "d1" {
		t.Fatalf("u1 devices = %+v, want just d1", d1)
	}
	if got := h.Devices("u3"); len(got) != 0 {
		t.Errorf("unknown user devices = %+v, want empty", got)
	}
}

func TestPublishStateRejectsNonActiveDevice(t *testing.T) {
	h := testHub()
	join(t, h, "u1", "d1")
	join(t, h, "u1", "d2")
	if _, err := h.Transfer("u1", "d1", true); err != nil {
		t.Fatal(err)
	}

	if _, err := h.PublishState("u1", "d2", PlaybackState{IsPlaying: true}); !errors.Is(err, ErrNotActive) {
		t.Fatalf("err = %v, want ErrNotActive", err)
	}

	// The rejected publish must not consume a revision.
	st, err := h.PublishState("u1", "d1", PlaybackState{IsPlaying: true})
	if err != nil {
		t.Fatal(err)
	}
	if st.Rev != 2 { // 1 from the transfer, 2 from this publish
		t.Errorf("rev = %d, want 2", st.Rev)
	}
}

func TestTransferAnnouncesToEveryDevice(t *testing.T) {
	h := testHub()
	a := join(t, h, "u1", "d1")
	b := join(t, h, "u1", "d2")

	if _, err := h.Transfer("u1", "d2", true); err != nil {
		t.Fatal(err)
	}

	for name, ch := range map[string]<-chan Event{"d1": a, "d2": b} {
		ev := waitFor(t, ch, EventTransfer)
		tr, ok := ev.Data.(Transfer)
		if !ok {
			t.Fatalf("%s: data type %T, want Transfer", name, ev.Data)
		}
		if tr.ActiveDeviceID != "d2" {
			t.Errorf("%s: active = %q, want d2", name, tr.ActiveDeviceID)
		}
	}
}

func TestCommandCannotCrossUsers(t *testing.T) {
	h := testHub()
	join(t, h, "u1", "d1")
	join(t, h, "u2", "other")

	err := h.SendCommand("u1", "d1", "other", Command{Type: "pause"})
	if !errors.Is(err, ErrDeviceNotFound) {
		t.Fatalf("err = %v, want ErrDeviceNotFound", err)
	}
}

func TestCommandRoutesToActiveDeviceOnly(t *testing.T) {
	h := testHub()
	a := join(t, h, "u1", "d1")
	b := join(t, h, "u1", "d2")
	if _, err := h.Transfer("u1", "d1", true); err != nil {
		t.Fatal(err)
	}
	// Drain the transfer/devices events.
	waitFor(t, a, EventTransfer)
	waitFor(t, b, EventTransfer)

	if err := h.SendCommand("u1", "d2", "", Command{Type: "next"}); err != nil {
		t.Fatal(err)
	}

	ev := waitFor(t, a, EventCommand)
	cmd := ev.Data.(Command)
	if cmd.Type != "next" || cmd.From != "d2" {
		t.Errorf("cmd = %+v, want next from d2", cmd)
	}

	// The sender must not receive its own command back.
	select {
	case ev := <-b:
		if ev.Name == EventCommand {
			t.Error("command echoed to sender")
		}
	case <-time.After(50 * time.Millisecond):
	}
}

func TestUnknownCommandTypeIsRejected(t *testing.T) {
	h := testHub()
	join(t, h, "u1", "d1")
	if _, err := h.Transfer("u1", "d1", true); err != nil {
		t.Fatal(err)
	}
	if err := h.SendCommand("u1", "d1", "", Command{Type: "selfDestruct"}); !errors.Is(err, ErrInvalidCommand) {
		t.Fatalf("err = %v, want ErrInvalidCommand", err)
	}
}

func TestSweepExpiresDeviceAndReleasesActiveRole(t *testing.T) {
	h := testHub()
	now := time.Now()
	h.now = func() time.Time { return now }

	survivor := join(t, h, "u1", "d1")
	join(t, h, "u1", "dead")
	if _, err := h.Transfer("u1", "dead", true); err != nil {
		t.Fatal(err)
	}
	waitFor(t, survivor, EventTransfer)

	// d1 keeps heartbeating; "dead" does not.
	now = now.Add(DeviceTTL + time.Second)
	if err := h.Touch("u1", "d1"); err != nil {
		t.Fatal(err)
	}
	h.sweep()

	devices := h.Devices("u1")
	if len(devices) != 1 || devices[0].ID != "d1" {
		t.Fatalf("devices = %+v, want just d1", devices)
	}
	ev := waitFor(t, survivor, EventTransfer)
	if tr := ev.Data.(Transfer); tr.ActiveDeviceID != "" {
		t.Errorf("active = %q, want empty after the active device expired", tr.ActiveDeviceID)
	}
}

func TestSlowSubscriberIsDroppedWithoutBlockingOthers(t *testing.T) {
	h := testHub()
	fast := join(t, h, "u1", "fast")
	slow := join(t, h, "u1", "slow")
	if _, err := h.Transfer("u1", "fast", true); err != nil {
		t.Fatal(err)
	}

	// Never read from `slow`; overflow its buffer.
	for i := 0; i < eventBuffer*2; i++ {
		if _, err := h.PublishState("u1", "fast", PlaybackState{PositionSec: float64(i)}); err != nil {
			t.Fatal(err)
		}
		// Keep the fast subscriber drained so only `slow` falls behind.
		for len(fast) > 0 {
			<-fast
		}
	}

	select {
	case _, ok := <-slow:
		for ok {
			_, ok = <-slow
		}
	case <-time.After(time.Second):
		t.Fatal("slow subscriber was never dropped")
	}

	// The fast subscriber still works.
	if _, err := h.PublishState("u1", "fast", PlaybackState{PositionSec: 99}); err != nil {
		t.Fatal(err)
	}
	if ev := waitFor(t, fast, EventState); ev.Data.(PlaybackState).PositionSec != 99 {
		t.Error("fast subscriber stopped receiving")
	}
}

// fakePersister records saves and serves one preloaded state.
type fakePersister struct {
	saved  map[string]PlaybackState
	stored PlaybackState
	found  bool
}

func (f *fakePersister) SavePlaybackState(_ context.Context, userID string, st PlaybackState) error {
	if f.saved == nil {
		f.saved = map[string]PlaybackState{}
	}
	f.saved[userID] = st
	return nil
}

func (f *fakePersister) LoadPlaybackState(_ context.Context, _ string) (PlaybackState, bool, error) {
	return f.stored, f.found, nil
}

func TestStateRestoresPersistedStatePausedOnce(t *testing.T) {
	p := &fakePersister{
		stored: PlaybackState{Rev: 7, IsPlaying: true, PositionSec: 12, QueueIndex: 3},
		found:  true,
	}
	h := New(slog.New(slog.NewTextHandler(io.Discard, nil)), p)

	st := h.State(context.Background(), "u1")
	if st.PositionSec != 12 || st.QueueIndex != 3 {
		t.Fatalf("state = %+v, want the persisted one", st)
	}
	if st.IsPlaying {
		t.Error("restored state must not claim to be playing: no device is")
	}

	// Second call must not hit the store again — flip the fake and check.
	p.stored = PlaybackState{PositionSec: 999}
	if st := h.State(context.Background(), "u1"); st.PositionSec != 12 {
		t.Errorf("position = %v, want the first load to stick", st.PositionSec)
	}
}

func TestFlushWritesOnlyDirtyUsers(t *testing.T) {
	p := &fakePersister{}
	h := New(slog.New(slog.NewTextHandler(io.Discard, nil)), p)
	join(t, h, "u1", "d1")
	if _, err := h.Transfer("u1", "d1", true); err != nil {
		t.Fatal(err)
	}

	h.Flush(context.Background())
	if len(p.saved) != 1 {
		t.Fatalf("saved %d users, want 1", len(p.saved))
	}

	p.saved = nil
	h.Flush(context.Background())
	if len(p.saved) != 0 {
		t.Errorf("saved %d users on a clean flush, want 0", len(p.saved))
	}
}

func TestDeviceLimit(t *testing.T) {
	h := testHub()
	for i := 0; i < MaxDevicesPerUser; i++ {
		if _, err := h.Register("u1", meta(string(rune('a'+i)))); err != nil {
			t.Fatalf("device %d: %v", i, err)
		}
	}
	if _, err := h.Register("u1", meta("overflow")); !errors.Is(err, ErrTooManyDevices) {
		t.Fatalf("err = %v, want ErrTooManyDevices", err)
	}
	// Re-registering an existing device is a heartbeat, not a new slot.
	if _, err := h.Register("u1", meta("a")); err != nil {
		t.Errorf("re-register: %v", err)
	}
}
