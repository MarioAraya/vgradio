// Package imageutil provides image resizing for cover art display versions.
package imageutil

import (
	"image"
	"image/jpeg"
	"image/png"
	_ "image/gif"
	"io"
	"os"
	"strings"

	"golang.org/x/image/draw"
)

// MaxDisplay is the longest edge in pixels for the display (web-served) version.
const MaxDisplay = 400

// ResizeToDisplay decodes src, scales it so the longest edge ≤ MaxDisplay,
// and encodes the result to dst. Format is preserved (JPEG/PNG); others become JPEG.
// If src is already small enough, dst is a straight copy.
func ResizeToDisplay(src, dst string) error {
	sf, err := os.Open(src)
	if err != nil {
		return err
	}
	img, format, err := image.Decode(sf)
	sf.Close()
	if err != nil {
		return err
	}

	b := img.Bounds()
	w, h := b.Dx(), b.Dy()

	if w <= MaxDisplay && h <= MaxDisplay {
		return copyFile(src, dst)
	}

	longest := w
	if h > longest {
		longest = h
	}
	scale := float64(MaxDisplay) / float64(longest)
	nw := max(1, int(float64(w)*scale))
	nh := max(1, int(float64(h)*scale))

	out := image.NewRGBA(image.Rect(0, 0, nw, nh))
	draw.BiLinear.Scale(out, out.Bounds(), img, img.Bounds(), draw.Over, nil)

	df, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer df.Close()

	if strings.ToLower(format) == "png" {
		return png.Encode(df, out)
	}
	return jpeg.Encode(df, out, &jpeg.Options{Quality: 88})
}

// CopyIfMissing copies src to dst only if dst does not already exist.
func CopyIfMissing(src, dst string) error {
	if _, err := os.Stat(dst); err == nil {
		return nil
	}
	return copyFile(src, dst)
}

func copyFile(src, dst string) error {
	sf, err := os.Open(src)
	if err != nil {
		return err
	}
	defer sf.Close()
	df, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer df.Close()
	_, err = io.Copy(df, sf)
	return err
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
