package imgprep

import (
	"bytes"
	"encoding/binary"
	"image"
	"image/color"
	"image/jpeg"
	"testing"
)

// quadrants is a 64×32 photo: red top-left, green top-right, blue
// bottom-left, white bottom-right.
func quadrants() image.Image {
	img := image.NewNRGBA(image.Rect(0, 0, 64, 32))
	for y := 0; y < 32; y++ {
		for x := 0; x < 64; x++ {
			c := color.NRGBA{255, 0, 0, 255}
			switch {
			case x >= 32 && y < 16:
				c = color.NRGBA{0, 255, 0, 255}
			case x < 32 && y >= 16:
				c = color.NRGBA{0, 0, 255, 255}
			case x >= 32 && y >= 16:
				c = color.NRGBA{255, 255, 255, 255}
			}
			img.Set(x, y, c)
		}
	}
	return img
}

// withExif returns a JPEG of img with an EXIF block holding orientation o
// and a GPS pointer, as phone cameras write.
func withExif(t *testing.T, img image.Image, o uint16) []byte {
	t.Helper()
	var plain bytes.Buffer
	if err := jpeg.Encode(&plain, img, &jpeg.Options{Quality: 95}); err != nil {
		t.Fatal(err)
	}
	tiff := []byte("MM\x00\x2a\x00\x00\x00\x08")
	ifd := make([]byte, 2+2*12+4)
	binary.BigEndian.PutUint16(ifd, 2)
	// Orientation (SHORT).
	binary.BigEndian.PutUint16(ifd[2:], 0x0112)
	binary.BigEndian.PutUint16(ifd[4:], 3)
	binary.BigEndian.PutUint32(ifd[6:], 1)
	binary.BigEndian.PutUint16(ifd[10:], o)
	// GPS IFD pointer (LONG), to a block with the latitude reference.
	binary.BigEndian.PutUint16(ifd[14:], 0x8825)
	binary.BigEndian.PutUint16(ifd[16:], 4)
	binary.BigEndian.PutUint32(ifd[18:], 1)
	binary.BigEndian.PutUint32(ifd[22:], uint32(8+len(ifd)))
	gps := []byte{0, 1, 0, 1, 0, 2, 0, 0, 0, 2, 'S', 0, 0, 0, 0, 0, 0, 0}
	payload := append([]byte("Exif\x00\x00"), append(tiff, append(ifd, gps...)...)...)
	segment := []byte{0xFF, 0xE1, 0, 0}
	binary.BigEndian.PutUint16(segment[2:], uint16(2+len(payload)))
	src := plain.Bytes()
	out := append([]byte{}, src[:2]...)
	out = append(out, segment...)
	out = append(out, payload...)
	return append(out, src[2:]...)
}

// near reports whether a pixel is close to c (JPEG blurs a little).
func near(img image.Image, x, y int, c color.NRGBA) bool {
	r, g, b, _ := img.At(x, y).RGBA()
	d := func(a uint32, want uint8) bool {
		diff := int(a>>8) - int(want)
		return diff > -60 && diff < 60
	}
	return d(r, c.R) && d(g, c.G) && d(b, c.B)
}

var (
	red   = color.NRGBA{255, 0, 0, 255}
	green = color.NRGBA{0, 255, 0, 255}
	blue  = color.NRGBA{0, 0, 255, 255}
	white = color.NRGBA{255, 255, 255, 255}
)

func TestOrientationIsReadAndApplied(t *testing.T) {
	// For each orientation: the size after turning it upright and the
	// colors at the four corners (top-left, top-right, bottom-left,
	// bottom-right) of the result.
	cases := []struct {
		o      uint16
		w, h   int
		corner [4]color.NRGBA
	}{
		{1, 64, 32, [4]color.NRGBA{red, green, blue, white}},
		{2, 64, 32, [4]color.NRGBA{green, red, white, blue}},
		{3, 64, 32, [4]color.NRGBA{white, blue, green, red}},
		{4, 64, 32, [4]color.NRGBA{blue, white, red, green}},
		{5, 32, 64, [4]color.NRGBA{red, blue, green, white}},
		{6, 32, 64, [4]color.NRGBA{blue, red, white, green}},
		{7, 32, 64, [4]color.NRGBA{white, green, blue, red}},
		{8, 32, 64, [4]color.NRGBA{green, white, red, blue}},
	}
	for _, c := range cases {
		data := withExif(t, quadrants(), c.o)
		if got := Orientation(data); got != int(c.o) {
			t.Fatalf("orientation %d read as %d", c.o, got)
		}
		photo, thumb, w, h, err := Prepare(data)
		if err != nil {
			t.Fatal(err)
		}
		if w != c.w || h != c.h {
			t.Fatalf("orientation %d: %dx%d", c.o, w, h)
		}
		img, err := jpeg.Decode(bytes.NewReader(photo))
		if err != nil {
			t.Fatal(err)
		}
		corners := [4][2]int{{2, 2}, {w - 3, 2}, {2, h - 3}, {w - 3, h - 3}}
		for i, p := range corners {
			if !near(img, p[0], p[1], c.corner[i]) {
				t.Errorf("orientation %d corner %d = %v", c.o, i, img.At(p[0], p[1]))
			}
		}
		if len(thumb) == 0 {
			t.Fatalf("orientation %d: no thumbnail", c.o)
		}
	}
}

func TestPreparedPhotoHasNoMetadata(t *testing.T) {
	photo, thumb, _, _, err := Prepare(withExif(t, quadrants(), 6))
	if err != nil {
		t.Fatal(err)
	}
	for _, out := range [][]byte{photo, thumb} {
		if bytes.Contains(out, []byte("Exif")) || bytes.Contains(out, []byte{0xFF, 0xE1}) {
			t.Fatal("EXIF (and the location in it) survived")
		}
		if Orientation(out) != 1 {
			t.Fatal("orientation tag survived")
		}
	}
}

func TestLargePhotosAreCappedAndThumbnailsSmall(t *testing.T) {
	big := image.NewNRGBA(image.Rect(0, 0, 3200, 1200))
	var src bytes.Buffer
	jpeg.Encode(&src, big, nil)
	photo, thumb, w, h, err := Prepare(src.Bytes())
	if err != nil || w != MaxSide || h != 600 {
		t.Fatalf("size %dx%d, %v", w, h, err)
	}
	ti, _ := jpeg.Decode(bytes.NewReader(thumb))
	if b := ti.Bounds(); b.Dx() != ThumbSide || b.Dy() != 37 {
		t.Fatalf("thumbnail %v", b)
	}
	if len(photo) == 0 {
		t.Fatal("empty photo")
	}
}

func TestNotAPhoto(t *testing.T) {
	if _, _, _, _, err := Prepare([]byte("%PDF-1.4")); err != ErrNotPhoto {
		t.Fatalf("err = %v", err)
	}
	if Orientation([]byte{1, 2, 3}) != 1 {
		t.Fatal("garbage has an orientation")
	}
}
