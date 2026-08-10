package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestIsLongWrite(t *testing.T) {
	long := []string{
		"/tracks/trk_001/stream",
		"/tracks/trk_001/download",
		"/tracks/trk_001/fetch",
		"/albums/alb_7f3a/covers.zip",
		"/albums/alb_7f3a/scrape-tracks",
		"/scrape/pending",
		"/connect/events",
	}
	for _, p := range long {
		if !isLongWrite(p) {
			t.Errorf("isLongWrite(%q) = false, want true", p)
		}
	}

	short := []string{
		"/albums",
		"/albums/alb_7f3a",
		"/catalog",
		"/catalog/sync",
		"/health",
		"/covers/alb_7f3a/0.jpg",
		"/auth/login",
	}
	for _, p := range short {
		if isLongWrite(p) {
			t.Errorf("isLongWrite(%q) = true, want false", p)
		}
	}
}

// deadlineWriter records SetWriteDeadline calls, standing in for the real
// connection-backed ResponseWriter (httptest.ResponseRecorder has no deadline
// support).
type deadlineWriter struct {
	http.ResponseWriter
	set bool
}

func (dw *deadlineWriter) SetWriteDeadline(time.Time) error {
	dw.set = true
	return nil
}

// statusWriter wraps the real writer, so without Unwrap the ResponseController
// inside writeDeadline can no longer reach SetWriteDeadline.
func TestStatusWriterUnwrap_AllowsWriteDeadline(t *testing.T) {
	dw := &deadlineWriter{ResponseWriter: httptest.NewRecorder()}
	sw := &statusWriter{ResponseWriter: dw, code: 200}

	if err := http.NewResponseController(sw).SetWriteDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatalf("SetWriteDeadline through statusWriter: %v", err)
	}
	if !dw.set {
		t.Error("deadline did not reach the underlying writer")
	}
}
