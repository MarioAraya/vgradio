// Package connect implements VGRadio Connect: cross-instance remote control.
//
// The hub is a relay with state, not a player. It never interprets the queue and
// never resolves tracks — clients own shuffle, repeat and hidden-track logic.
// The hub knows three things: which devices a user has, which one is active, and
// the playback state the active device last published.
package connect

import (
	"encoding/json"
	"errors"
	"time"
)

// Limits. Devices are ephemeral: they are never persisted and expire by TTL.
const (
	MaxDevicesPerUser = 8
	DeviceTTL         = 45 * time.Second
	SweepInterval     = 15 * time.Second
	// eventBuffer is per subscriber. A client that falls this far behind is
	// dropped rather than allowed to block the publisher.
	eventBuffer = 32
)

var (
	ErrDeviceNotFound = errors.New("connect: device not found")
	ErrNotActive      = errors.New("connect: device is not the active one")
	ErrTooManyDevices = errors.New("connect: device limit reached")
	ErrInvalidCommand = errors.New("connect: unknown command type")
)

// DeviceMeta is what a client declares about itself when registering.
type DeviceMeta struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Type         string   `json:"type"` // macos | web | tv
	Capabilities []string `json:"capabilities,omitempty"`
}

// Device is DeviceMeta plus hub-owned fields.
type Device struct {
	DeviceMeta
	IsActive bool      `json:"isActive"`
	LastSeen time.Time `json:"lastSeen"`
}

// QueueEntry identifies a queued track. Only IDs travel: clients hydrate album
// metadata through the existing /albums/{id} endpoint, which they already cache.
// Sending full track+cover objects would be an order of magnitude more bytes per
// update for a large album.
type QueueEntry struct {
	TrackID string `json:"trackId"`
	AlbumID string `json:"albumId"`
}

// PlaybackState is the user's playback state, owned by the active device.
// Rev is assigned by the hub and increases monotonically per user.
type PlaybackState struct {
	Rev         int64        `json:"rev"`
	DeviceID    string       `json:"deviceId"`
	IsPlaying   bool         `json:"isPlaying"`
	PositionSec float64      `json:"positionSec"`
	UpdatedAt   time.Time    `json:"updatedAt"`
	Volume      float64      `json:"volume"`
	IsMuted     bool         `json:"isMuted"`
	IsShuffle   bool         `json:"isShuffle"`
	RepeatMode  string       `json:"repeatMode"` // off | all | one
	QueueIndex  int          `json:"queueIndex"`
	CoverIndex  int          `json:"coverIndex"`
	Queue       []QueueEntry `json:"queue"`
}

// Command is an order routed to a device. The hub does not interpret Payload.
type Command struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
	From    string          `json:"from,omitempty"`
}

// commandTypes is an allowlist so a typo in a client fails loudly at the hub
// instead of being delivered and silently ignored by the target.
var commandTypes = map[string]bool{
	"play": true, "pause": true, "toggle": true,
	"next": true, "prev": true, "seek": true,
	"volume": true, "mute": true, "shuffle": true, "repeat": true,
	"playContext": true,
	"queueAdd":    true, "queueRemove": true, "queueMove": true,
}

// Event names pushed over SSE.
const (
	EventHello    = "hello"
	EventState    = "state"
	EventDevices  = "devices"
	EventCommand  = "command"
	EventTransfer = "transfer"
)

// Event is one SSE message. Data is marshalled by the transport layer.
type Event struct {
	Name string
	Data any
}

// Hello is the snapshot sent to a device right after it subscribes.
type Hello struct {
	DeviceID       string        `json:"deviceId"`
	ActiveDeviceID string        `json:"activeDeviceId"`
	State          PlaybackState `json:"state"`
	Devices        []Device      `json:"devices"`
}

// Transfer announces a change of active device.
type Transfer struct {
	ActiveDeviceID string        `json:"activeDeviceId"`
	Play           bool          `json:"play"`
	State          PlaybackState `json:"state"`
}
