package connect

import (
	"context"
	"log/slog"
	"sync"
	"time"
)

// Persister stores playback state across backend restarts. Optional: a nil
// Persister just means state is lost on restart.
type Persister interface {
	SavePlaybackState(ctx context.Context, userID string, state PlaybackState) error
	LoadPlaybackState(ctx context.Context, userID string) (PlaybackState, bool, error)
}

type subscriber struct {
	deviceID string
	ch       chan Event
}

type device struct {
	meta     DeviceMeta
	lastSeen time.Time
}

type userHub struct {
	devices map[string]*device
	subs    map[*subscriber]struct{}
	active  string
	state   PlaybackState
	rev     int64
	// dirty means state changed since the last persist.
	dirty bool
	// loaded means we already tried to restore persisted state for this user.
	loaded bool
}

// Hub fans events out to every device of a user. All exported methods are safe
// for concurrent use.
type Hub struct {
	mu    sync.Mutex
	users map[string]*userHub
	log   *slog.Logger
	store Persister
	now   func() time.Time
}

func New(log *slog.Logger, store Persister) *Hub {
	if log == nil {
		log = slog.Default()
	}
	return &Hub{
		users: make(map[string]*userHub),
		log:   log,
		store: store,
		now:   time.Now,
	}
}

// userLocked returns the user's hub, creating it if needed. Caller holds h.mu.
func (h *Hub) userLocked(userID string) *userHub {
	u, ok := h.users[userID]
	if !ok {
		u = &userHub{
			devices: make(map[string]*device),
			subs:    make(map[*subscriber]struct{}),
		}
		h.users[userID] = u
	}
	return u
}

// Register adds or refreshes a device. Re-registering an existing ID is the
// heartbeat path, so it must not disturb the active device or the state.
func (h *Hub) Register(userID string, meta DeviceMeta) (Device, error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	u := h.userLocked(userID)
	d, existed := u.devices[meta.ID]
	if !existed {
		if len(u.devices) >= MaxDevicesPerUser {
			return Device{}, ErrTooManyDevices
		}
		d = &device{}
		u.devices[meta.ID] = d
	}
	d.meta = meta
	d.lastSeen = h.now()

	if !existed {
		h.broadcastLocked(u, Event{Name: EventDevices, Data: h.devicesLocked(u)})
	}
	return Device{DeviceMeta: meta, IsActive: u.active == meta.ID, LastSeen: d.lastSeen}, nil
}

// Touch refreshes a device's TTL without re-sending its metadata.
func (h *Hub) Touch(userID, deviceID string) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	u, ok := h.users[userID]
	if !ok {
		return ErrDeviceNotFound
	}
	d, ok := u.devices[deviceID]
	if !ok {
		return ErrDeviceNotFound
	}
	d.lastSeen = h.now()
	return nil
}

// Unregister removes a device (clean shutdown). Releasing the active role is
// announced so the other devices can offer to take over.
func (h *Hub) Unregister(userID, deviceID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	u, ok := h.users[userID]
	if !ok {
		return
	}
	h.dropDeviceLocked(u, deviceID)
}

func (h *Hub) dropDeviceLocked(u *userHub, deviceID string) {
	if _, ok := u.devices[deviceID]; !ok {
		return
	}
	delete(u.devices, deviceID)
	if u.active == deviceID {
		u.active = ""
		u.state.IsPlaying = false
		h.broadcastLocked(u, Event{Name: EventTransfer, Data: Transfer{ActiveDeviceID: "", State: u.state}})
	}
	h.broadcastLocked(u, Event{Name: EventDevices, Data: h.devicesLocked(u)})
}

// Devices lists the user's live devices.
func (h *Hub) Devices(userID string) []Device {
	h.mu.Lock()
	defer h.mu.Unlock()
	u, ok := h.users[userID]
	if !ok {
		return []Device{}
	}
	return h.devicesLocked(u)
}

func (h *Hub) devicesLocked(u *userHub) []Device {
	out := make([]Device, 0, len(u.devices))
	for id, d := range u.devices {
		out = append(out, Device{DeviceMeta: d.meta, IsActive: u.active == id, LastSeen: d.lastSeen})
	}
	return out
}

// Subscribe returns the device's event channel plus a cancel func. The device
// must be registered first. The returned channel is closed by cancel only.
func (h *Hub) Subscribe(userID, deviceID string) (<-chan Event, func(), error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	u, ok := h.users[userID]
	if !ok {
		return nil, nil, ErrDeviceNotFound
	}
	d, ok := u.devices[deviceID]
	if !ok {
		return nil, nil, ErrDeviceNotFound
	}
	d.lastSeen = h.now()

	sub := &subscriber{deviceID: deviceID, ch: make(chan Event, eventBuffer)}
	u.subs[sub] = struct{}{}

	// Snapshot first, so the client never renders an empty player before the
	// first state event arrives.
	sub.ch <- Event{Name: EventHello, Data: Hello{
		DeviceID:       deviceID,
		ActiveDeviceID: u.active,
		State:          u.state,
		Devices:        h.devicesLocked(u),
	}}

	cancel := func() {
		h.mu.Lock()
		defer h.mu.Unlock()
		if _, still := u.subs[sub]; still {
			delete(u.subs, sub)
			close(sub.ch)
		}
	}
	return sub.ch, cancel, nil
}

// PublishState records state from the active device. A device that is not active
// is rejected: without that rule two devices could interleave writes after a
// transfer and the rev counter would stop meaning anything.
func (h *Hub) PublishState(userID, deviceID string, st PlaybackState) (PlaybackState, error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	u, ok := h.users[userID]
	if !ok {
		return PlaybackState{}, ErrDeviceNotFound
	}
	d, ok := u.devices[deviceID]
	if !ok {
		return PlaybackState{}, ErrDeviceNotFound
	}
	d.lastSeen = h.now()
	if u.active != deviceID {
		return PlaybackState{}, ErrNotActive
	}

	u.rev++
	st.Rev = u.rev
	st.DeviceID = deviceID
	st.UpdatedAt = h.now()
	u.state = st
	u.dirty = true

	h.broadcastLocked(u, Event{Name: EventState, Data: st})

	// Persist immediately on pause: that is the state a user most expects to find
	// when they come back, and waiting for the ticker risks losing it to a
	// restart. Flush blocks on h.mu, so it runs once this call releases it.
	if !st.IsPlaying && h.store != nil {
		go h.Flush(context.Background())
	}
	return st, nil
}

// Transfer makes deviceID the active device and announces it. The previous
// active device stops on receiving the event; it is not asked first, which is
// what makes "play here instead" feel instant.
func (h *Hub) Transfer(userID, deviceID string, play bool) (PlaybackState, error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	u, ok := h.users[userID]
	if !ok {
		return PlaybackState{}, ErrDeviceNotFound
	}
	if _, ok := u.devices[deviceID]; !ok {
		return PlaybackState{}, ErrDeviceNotFound
	}

	u.active = deviceID
	u.rev++
	u.state.Rev = u.rev
	u.state.DeviceID = deviceID
	u.state.UpdatedAt = h.now()
	u.dirty = true

	h.broadcastLocked(u, Event{Name: EventTransfer, Data: Transfer{
		ActiveDeviceID: deviceID, Play: play, State: u.state,
	}})
	h.broadcastLocked(u, Event{Name: EventDevices, Data: h.devicesLocked(u)})
	return u.state, nil
}

// SendCommand routes a command to target, or to the active device when target is
// empty. Commands are only ever delivered inside the sender's own user hub.
func (h *Hub) SendCommand(userID, fromDeviceID, targetDeviceID string, cmd Command) error {
	if !commandTypes[cmd.Type] {
		return ErrInvalidCommand
	}

	h.mu.Lock()
	defer h.mu.Unlock()

	u, ok := h.users[userID]
	if !ok {
		return ErrDeviceNotFound
	}
	if d, ok := u.devices[fromDeviceID]; ok {
		d.lastSeen = h.now()
	} else {
		return ErrDeviceNotFound
	}

	target := targetDeviceID
	if target == "" {
		target = u.active
	}
	if target == "" {
		return ErrDeviceNotFound
	}
	if _, ok := u.devices[target]; !ok {
		return ErrDeviceNotFound
	}

	cmd.From = fromDeviceID
	h.sendToLocked(u, target, Event{Name: EventCommand, Data: cmd})
	return nil
}

// State returns the user's current playback state, restoring the persisted one
// the first time a user is seen after a restart.
func (h *Hub) State(ctx context.Context, userID string) PlaybackState {
	h.mu.Lock()
	u := h.userLocked(userID)
	if u.loaded || h.store == nil {
		st := u.state
		h.mu.Unlock()
		return st
	}
	u.loaded = true
	h.mu.Unlock()

	st, found, err := h.store.LoadPlaybackState(ctx, userID)
	if err != nil {
		h.log.Warn("connect: load state", "err", err)
		return PlaybackState{}
	}

	h.mu.Lock()
	defer h.mu.Unlock()
	u = h.userLocked(userID)
	// A device may have published while we were reading; newer wins.
	if found && u.rev == 0 {
		st.IsPlaying = false // nothing is actually playing after a restart
		u.state = st
		u.rev = st.Rev
	}
	return u.state
}

// sendToLocked delivers to one device's subscribers. Caller holds h.mu.
func (h *Hub) sendToLocked(u *userHub, deviceID string, ev Event) {
	for sub := range u.subs {
		if sub.deviceID != deviceID {
			continue
		}
		h.offerLocked(u, sub, ev)
	}
}

// broadcastLocked delivers to every subscriber of the user. Caller holds h.mu.
func (h *Hub) broadcastLocked(u *userHub, ev Event) {
	for sub := range u.subs {
		h.offerLocked(u, sub, ev)
	}
}

// offerLocked never blocks: a subscriber whose buffer is full is disconnected.
// Blocking here would let one stalled HTTP client freeze every other device.
func (h *Hub) offerLocked(u *userHub, sub *subscriber, ev Event) {
	select {
	case sub.ch <- ev:
	default:
		h.log.Warn("connect: subscriber too slow, dropping", "device", sub.deviceID)
		delete(u.subs, sub)
		close(sub.ch)
	}
}

// Run sweeps expired devices and flushes dirty state until ctx is done.
func (h *Hub) Run(ctx context.Context) {
	t := time.NewTicker(SweepInterval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			h.Flush(context.WithoutCancel(ctx))
			return
		case <-t.C:
			h.sweep()
			h.Flush(ctx)
		}
	}
}

// sweep drops devices that stopped sending heartbeats.
func (h *Hub) sweep() {
	h.mu.Lock()
	defer h.mu.Unlock()
	cutoff := h.now().Add(-DeviceTTL)
	for _, u := range h.users {
		for id, d := range u.devices {
			if d.lastSeen.Before(cutoff) {
				h.log.Info("connect: device expired", "device", id)
				h.dropDeviceLocked(u, id)
			}
		}
	}
}

// Flush persists state for users whose state changed since the last flush.
func (h *Hub) Flush(ctx context.Context) {
	if h.store == nil {
		return
	}
	type pending struct {
		userID string
		state  PlaybackState
	}
	h.mu.Lock()
	var todo []pending
	for id, u := range h.users {
		if u.dirty {
			u.dirty = false
			todo = append(todo, pending{id, u.state})
		}
	}
	h.mu.Unlock()

	for _, p := range todo {
		if err := h.store.SavePlaybackState(ctx, p.userID, p.state); err != nil {
			h.log.Warn("connect: save state", "user", p.userID, "err", err)
		}
	}
}
