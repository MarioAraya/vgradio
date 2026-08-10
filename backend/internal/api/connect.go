package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/arayama/vgradio-app/backend/internal/connect"
)

// sseKeepalive bounds how long a proxy or NAT may see an idle connection.
const sseKeepalive = 15 * time.Second

// connectStatus maps hub errors to HTTP codes. A device belonging to another
// user is reported as 404, not 403: the caller must not be able to probe which
// device IDs exist.
func connectStatus(err error) int {
	switch {
	case errors.Is(err, connect.ErrDeviceNotFound):
		return http.StatusNotFound
	case errors.Is(err, connect.ErrNotActive):
		return http.StatusConflict
	case errors.Is(err, connect.ErrTooManyDevices):
		return http.StatusTooManyRequests
	case errors.Is(err, connect.ErrInvalidCommand):
		return http.StatusBadRequest
	default:
		return http.StatusInternalServerError
	}
}

// POST /connect/devices — register or heartbeat a device.
func (h *handler) postConnectDevice(w http.ResponseWriter, r *http.Request) {
	var meta connect.DeviceMeta
	if err := json.NewDecoder(r.Body).Decode(&meta); err != nil {
		jsonError(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if meta.ID == "" {
		jsonError(w, "id is required", http.StatusBadRequest)
		return
	}
	if meta.Name == "" {
		meta.Name = "Unnamed device"
	}
	d, err := h.hub.Register(userIDFromCtx(r.Context()), meta)
	if err != nil {
		jsonError(w, err.Error(), connectStatus(err))
		return
	}
	jsonOK(w, d, http.StatusOK)
}

// DELETE /connect/devices/{id} — clean shutdown.
func (h *handler) deleteConnectDevice(w http.ResponseWriter, r *http.Request) {
	h.hub.Unregister(userIDFromCtx(r.Context()), r.PathValue("id"))
	w.WriteHeader(http.StatusNoContent)
}

// GET /connect/devices — the user's live devices.
func (h *handler) getConnectDevices(w http.ResponseWriter, r *http.Request) {
	jsonOK(w, h.hub.Devices(userIDFromCtx(r.Context())), http.StatusOK)
}

// POST /connect/state — publish state. Only the active device may.
func (h *handler) postConnectState(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("deviceId")
	if deviceID == "" {
		jsonError(w, "deviceId is required", http.StatusBadRequest)
		return
	}
	var st connect.PlaybackState
	if err := json.NewDecoder(r.Body).Decode(&st); err != nil {
		jsonError(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	out, err := h.hub.PublishState(userIDFromCtx(r.Context()), deviceID, st)
	if err != nil {
		jsonError(w, err.Error(), connectStatus(err))
		return
	}
	jsonOK(w, out, http.StatusOK)
}

// POST /connect/command — route a command to the active device, or to the
// device named by targetDeviceId.
func (h *handler) postConnectCommand(w http.ResponseWriter, r *http.Request) {
	deviceID := r.URL.Query().Get("deviceId")
	if deviceID == "" {
		jsonError(w, "deviceId is required", http.StatusBadRequest)
		return
	}
	var body struct {
		TargetDeviceID string          `json:"targetDeviceId"`
		Type           string          `json:"type"`
		Payload        json.RawMessage `json:"payload"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonError(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	cmd := connect.Command{Type: body.Type, Payload: body.Payload}
	if err := h.hub.SendCommand(userIDFromCtx(r.Context()), deviceID, body.TargetDeviceID, cmd); err != nil {
		jsonError(w, err.Error(), connectStatus(err))
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

// POST /connect/transfer — claim the active role.
func (h *handler) postConnectTransfer(w http.ResponseWriter, r *http.Request) {
	var body struct {
		DeviceID string `json:"deviceId"`
		Play     bool   `json:"play"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		jsonError(w, "invalid JSON body", http.StatusBadRequest)
		return
	}
	if body.DeviceID == "" {
		jsonError(w, "deviceId is required", http.StatusBadRequest)
		return
	}
	st, err := h.hub.Transfer(userIDFromCtx(r.Context()), body.DeviceID, body.Play)
	if err != nil {
		jsonError(w, err.Error(), connectStatus(err))
		return
	}
	jsonOK(w, st, http.StatusOK)
}

// GET /connect/events — SSE stream of the user's events.
//
// Registers the device from the query string when it is unknown, so a client
// that reconnects after its TTL expired recovers without a second round trip.
func (h *handler) getConnectEvents(w http.ResponseWriter, r *http.Request) {
	userID := userIDFromCtx(r.Context())
	q := r.URL.Query()
	deviceID := q.Get("deviceId")
	if deviceID == "" {
		jsonError(w, "deviceId is required", http.StatusBadRequest)
		return
	}

	meta := connect.DeviceMeta{ID: deviceID, Name: q.Get("name"), Type: q.Get("type")}
	if meta.Name == "" {
		meta.Name = "Unnamed device"
	}
	if _, err := h.hub.Register(userID, meta); err != nil {
		jsonError(w, err.Error(), connectStatus(err))
		return
	}
	// Populate state from disk before the hello snapshot is built.
	h.hub.State(r.Context(), userID)

	events, cancel, err := h.hub.Subscribe(userID, deviceID)
	if err != nil {
		jsonError(w, err.Error(), connectStatus(err))
		return
	}
	defer cancel()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	// Defeats response buffering in reverse proxies that would otherwise hold
	// events until the (never-arriving) end of the body.
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)

	rc := http.NewResponseController(w)
	// This route is excluded from the write deadline (see isLongWrite); clear any
	// inherited one defensively so a stream can never be cut mid-flight.
	_ = rc.SetWriteDeadline(time.Time{})
	_ = rc.Flush()

	ping := time.NewTicker(sseKeepalive)
	defer ping.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case <-ping.C:
			if _, err := fmt.Fprint(w, ": ping\n\n"); err != nil {
				return
			}
			if err := rc.Flush(); err != nil {
				return
			}
			// A ping proves the device is alive even while nothing is published.
			_ = h.hub.Touch(userID, deviceID)
		case ev, ok := <-events:
			if !ok {
				return // dropped by the hub for falling behind
			}
			if err := writeSSE(w, ev); err != nil {
				return
			}
			if err := rc.Flush(); err != nil {
				return
			}
		}
	}
}

func writeSSE(w http.ResponseWriter, ev connect.Event) error {
	data, err := json.Marshal(ev.Data)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintf(w, "event: %s\ndata: %s\n\n", ev.Name, data)
	return err
}
