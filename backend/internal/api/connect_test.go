package api_test

import (
	"bufio"
	"encoding/json"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// sseClient reads `event:`/`data:` pairs off a live SSE response.
type sseClient struct {
	sc *bufio.Scanner
}

type sseEvent struct {
	name string
	data []byte
}

func (c *sseClient) next(t *testing.T) sseEvent {
	t.Helper()
	var ev sseEvent
	for c.sc.Scan() {
		line := c.sc.Text()
		switch {
		case strings.HasPrefix(line, "event: "):
			ev.name = strings.TrimPrefix(line, "event: ")
		case strings.HasPrefix(line, "data: "):
			ev.data = []byte(strings.TrimPrefix(line, "data: "))
		case line == "":
			if ev.name != "" {
				return ev
			}
		}
	}
	t.Fatalf("stream ended before an event arrived: %v", c.sc.Err())
	return ev
}

// connectSetup starts a real server (SSE needs a live connection, not a
// recorder) and returns a client already logged in as a fresh user.
func connectSetup(t *testing.T) (*httptest.Server, *http.Client) {
	t.Helper()
	router, _, _ := setup(t)
	srv := httptest.NewServer(router)
	t.Cleanup(srv.Close)

	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatal(err)
	}
	client := &http.Client{Jar: jar, Timeout: 5 * time.Second}

	body := `{"username":"tester","email":"tester@example.com","password":"hunter2hunter2"}`
	resp, err := client.Post(srv.URL+"/auth/register", "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		t.Fatalf("register: status %d", resp.StatusCode)
	}
	return srv, client
}

func openEvents(t *testing.T, srv *httptest.Server, client *http.Client, deviceID string) *sseClient {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, srv.URL+"/connect/events?deviceId="+deviceID+"&type=web", nil)
	if err != nil {
		t.Fatal(err)
	}
	// No client timeout on the stream itself: it is meant to stay open.
	streamClient := &http.Client{Jar: client.Jar}
	resp, err := streamClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { resp.Body.Close() })

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "text/event-stream" {
		t.Fatalf("Content-Type = %q, want text/event-stream", ct)
	}
	return &sseClient{sc: bufio.NewScanner(resp.Body)}
}

func TestConnectEvents_RequiresAuth(t *testing.T) {
	router, _, _ := setup(t)
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodGet, "/connect/events?deviceId=d1", nil)
	router.ServeHTTP(w, r)
	if w.Code != http.StatusUnauthorized {
		t.Errorf("status = %d, want 401", w.Code)
	}
}

func TestConnectEvents_RequiresDeviceID(t *testing.T) {
	srv, client := connectSetup(t)
	resp, err := client.Get(srv.URL + "/connect/events")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Errorf("status = %d, want 400", resp.StatusCode)
	}
}

// The stream must deliver the hello snapshot and then survive a later write.
// Regression guard for the server-wide WriteTimeout that used to kill it.
func TestConnectEvents_HelloThenStateSurvivesLaterWrite(t *testing.T) {
	srv, client := connectSetup(t)
	stream := openEvents(t, srv, client, "d1")

	hello := stream.next(t)
	if hello.name != "hello" {
		t.Fatalf("first event = %q, want hello", hello.name)
	}
	var snap struct {
		DeviceID string `json:"deviceId"`
	}
	if err := json.Unmarshal(hello.data, &snap); err != nil {
		t.Fatal(err)
	}
	if snap.DeviceID != "d1" {
		t.Errorf("hello deviceId = %q, want d1", snap.DeviceID)
	}

	post(t, client, srv.URL+"/connect/transfer", `{"deviceId":"d1","play":true}`, http.StatusOK)
	if ev := stream.next(t); ev.name != "transfer" {
		t.Fatalf("event = %q, want transfer", ev.name)
	}
	if ev := stream.next(t); ev.name != "devices" {
		t.Fatalf("event = %q, want devices", ev.name)
	}

	body := `{"isPlaying":true,"positionSec":12.5,"queue":[{"trackId":"trk_1","albumId":"alb_1"}]}`
	post(t, client, srv.URL+"/connect/state?deviceId=d1", body, http.StatusOK)

	ev := stream.next(t)
	if ev.name != "state" {
		t.Fatalf("event = %q, want state", ev.name)
	}
	var st struct {
		PositionSec float64 `json:"positionSec"`
		Rev         int64   `json:"rev"`
	}
	if err := json.Unmarshal(ev.data, &st); err != nil {
		t.Fatal(err)
	}
	if st.PositionSec != 12.5 {
		t.Errorf("positionSec = %v, want 12.5", st.PositionSec)
	}
	if st.Rev == 0 {
		t.Error("rev = 0, want a hub-assigned revision")
	}
}

func TestConnectState_RejectsNonActiveDevice(t *testing.T) {
	srv, client := connectSetup(t)
	post(t, client, srv.URL+"/connect/devices", `{"id":"d1","name":"Mac","type":"macos"}`, http.StatusOK)
	post(t, client, srv.URL+"/connect/devices", `{"id":"d2","name":"Web","type":"web"}`, http.StatusOK)
	post(t, client, srv.URL+"/connect/transfer", `{"deviceId":"d1"}`, http.StatusOK)

	post(t, client, srv.URL+"/connect/state?deviceId=d2", `{"isPlaying":true}`, http.StatusConflict)
}

func TestConnectCommand_UnknownDeviceIs404(t *testing.T) {
	srv, client := connectSetup(t)
	post(t, client, srv.URL+"/connect/devices", `{"id":"d1","name":"Mac","type":"macos"}`, http.StatusOK)
	post(t, client, srv.URL+"/connect/command?deviceId=d1",
		`{"targetDeviceId":"nope","type":"pause"}`, http.StatusNotFound)
}

func TestConnectCommand_UnknownTypeIs400(t *testing.T) {
	srv, client := connectSetup(t)
	post(t, client, srv.URL+"/connect/devices", `{"id":"d1","name":"Mac","type":"macos"}`, http.StatusOK)
	post(t, client, srv.URL+"/connect/transfer", `{"deviceId":"d1"}`, http.StatusOK)
	post(t, client, srv.URL+"/connect/command?deviceId=d1", `{"type":"selfDestruct"}`, http.StatusBadRequest)
}

func TestConnectDevices_ListAndUnregister(t *testing.T) {
	srv, client := connectSetup(t)
	post(t, client, srv.URL+"/connect/devices", `{"id":"d1","name":"Mac","type":"macos"}`, http.StatusOK)

	var devices []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	getJSON(t, client, srv.URL+"/connect/devices", &devices)
	if len(devices) != 1 || devices[0].Name != "Mac" {
		t.Fatalf("devices = %+v, want one named Mac", devices)
	}

	req, _ := http.NewRequest(http.MethodDelete, srv.URL+"/connect/devices/d1", nil)
	resp, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()

	getJSON(t, client, srv.URL+"/connect/devices", &devices)
	if len(devices) != 0 {
		t.Errorf("devices = %+v, want empty after unregister", devices)
	}
}

func post(t *testing.T, client *http.Client, url, body string, wantStatus int) {
	t.Helper()
	resp, err := client.Post(url, "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != wantStatus {
		t.Fatalf("POST %s: status = %d, want %d", url, resp.StatusCode, wantStatus)
	}
}

func getJSON(t *testing.T, client *http.Client, url string, out any) {
	t.Helper()
	resp, err := client.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		t.Fatal(err)
	}
}
