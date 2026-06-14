// Package auth provides password hashing, session ID generation, and input validation.
package auth

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"regexp"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
)

const bcryptCost = 12

var (
	reUsername = regexp.MustCompile(`^[a-zA-Z0-9_\-]{3,30}$`)
	reEmail    = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)
)

var (
	ErrInvalidUsername = errors.New("username must be 3–30 chars, letters/digits/-/_")
	ErrInvalidEmail    = errors.New("invalid email address")
	ErrWeakPassword    = errors.New("password must be at least 8 characters")
)

// HashPassword returns a bcrypt hash of password.
func HashPassword(password string) (string, error) {
	h, err := bcrypt.GenerateFromPassword([]byte(password), bcryptCost)
	return string(h), err
}

// CheckPassword reports whether password matches the stored bcrypt hash.
func CheckPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}

// NewID returns a cryptographically random 32-byte hex string suitable for
// use as a user ID or session token.
func NewID() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// ValidateUsername returns an error if s is not a valid username.
func ValidateUsername(s string) error {
	if !reUsername.MatchString(s) {
		return ErrInvalidUsername
	}
	return nil
}

// ValidateEmail returns an error if s is not a plausible email address.
func ValidateEmail(s string) error {
	if !reEmail.MatchString(strings.ToLower(s)) {
		return ErrInvalidEmail
	}
	return nil
}

// ValidatePassword returns an error if s is too short.
func ValidatePassword(s string) error {
	if utf8.RuneCountInString(s) < 8 {
		return ErrWeakPassword
	}
	return nil
}
