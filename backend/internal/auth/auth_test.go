package auth_test

import (
	"testing"

	"github.com/arayama/vgradio-app/backend/internal/auth"
)

func TestHashAndCheck(t *testing.T) {
	hash, err := auth.HashPassword("mysecretpass")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if !auth.CheckPassword(hash, "mysecretpass") {
		t.Error("CheckPassword: expected true for correct password")
	}
	if auth.CheckPassword(hash, "wrongpass") {
		t.Error("CheckPassword: expected false for wrong password")
	}
}

func TestNewID(t *testing.T) {
	a, err := auth.NewID()
	if err != nil {
		t.Fatalf("NewID: %v", err)
	}
	b, _ := auth.NewID()
	if a == b {
		t.Error("NewID: two consecutive IDs should not be equal")
	}
	if len(a) != 32 {
		t.Errorf("NewID: expected 32 hex chars, got %d", len(a))
	}
}

func TestValidateUsername(t *testing.T) {
	cases := []struct{ s string; ok bool }{
		{"alice", true},
		{"alice_123", true},
		{"alice-bob", true},
		{"al", false},   // too short
		{"a b", false},  // space
		{"", false},
	}
	for _, c := range cases {
		err := auth.ValidateUsername(c.s)
		if (err == nil) != c.ok {
			t.Errorf("ValidateUsername(%q): got err=%v, want ok=%v", c.s, err, c.ok)
		}
	}
}

func TestValidateEmail(t *testing.T) {
	cases := []struct{ s string; ok bool }{
		{"user@example.com", true},
		{"user+tag@sub.domain.io", true},
		{"notanemail", false},
		{"@nodomain.com", false},
		{"", false},
	}
	for _, c := range cases {
		err := auth.ValidateEmail(c.s)
		if (err == nil) != c.ok {
			t.Errorf("ValidateEmail(%q): got err=%v, want ok=%v", c.s, err, c.ok)
		}
	}
}

func TestValidatePassword(t *testing.T) {
	if err := auth.ValidatePassword("short"); err == nil {
		t.Error("expected error for short password")
	}
	if err := auth.ValidatePassword("longenough"); err != nil {
		t.Errorf("unexpected error for valid password: %v", err)
	}
}
