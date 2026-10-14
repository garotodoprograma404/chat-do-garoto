// Package imgprep prepares photos to send: it applies
// the EXIF orientation, caps the size and encodes a new JPEG without any
// metadata (no location), plus a small thumbnail. Standard library only.
package imgprep

import (
	"bytes"
	"encoding/binary"
	"errors"
	"image"
	"image/jpeg"
	_ "image/png" // photos from the gallery may be PNG
)

const (
	// MaxSide caps the longest side of a sent photo, like WhatsApp.
	MaxSide = 1600
	// ThumbSide is the longest side of the preview in the message.
	ThumbSide = 100
)

// ErrNotPhoto means the bytes are not a JPEG or PNG image.
var ErrNotPhoto = errors.New("not a photo")

// Prepare returns the photo ready to send and its thumbnail, both JPEG
// without metadata, and the photo's size.
func Prepare(data []byte) (photo, thumb []byte, width, height int, err error) {
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, nil, 0, 0, ErrNotPhoto
	}
	img = Orient(img, Orientation(data))
	img = Fit(img, MaxSide)
	var out bytes.Buffer
	if err := jpeg.Encode(&out, img, &jpeg.Options{Quality: 82}); err != nil {
		return nil, nil, 0, 0, err
	}
	var small bytes.Buffer
	if err := jpeg.Encode(&small, Fit(img, ThumbSide), &jpeg.Options{Quality: 60}); err != nil {
		return nil, nil, 0, 0, err
	}
	b := img.Bounds()
	return out.Bytes(), small.Bytes(), b.Dx(), b.Dy(), nil
}

// Orientation reads the EXIF orientation of a JPEG (1 to 8); 1 when there
// is none.
func Orientation(data []byte) int {
	if len(data) < 4 || data[0] != 0xFF || data[1] != 0xD8 {
		return 1
	}
	for i := 2; i+4 <= len(data); {
		if data[i] != 0xFF {
			return 1
		}
		marker := data[i+1]
		if marker == 0xDA || marker == 0xD9 { // image data starts: no EXIF
			return 1
		}
		size := int(binary.BigEndian.Uint16(data[i+2:]))
		if size < 2 || i+2+size > len(data) {
			return 1
		}
		segment := data[i+4 : i+2+size]
		if marker == 0xE1 && bytes.HasPrefix(segment, []byte("Exif\x00\x00")) {
			return tiffOrientation(segment[6:])
		}
		i += 2 + size
	}
	return 1
}

// tiffOrientation finds tag 0x0112 in the first IFD of a TIFF block.
func tiffOrientation(t []byte) int {
	if len(t) < 8 {
		return 1
	}
	var order binary.ByteOrder
	switch string(t[:2]) {
	case "II":
		order = binary.LittleEndian
	case "MM":
		order = binary.BigEndian
	default:
		return 1
	}
	ifd := int(order.Uint32(t[4:]))
	if ifd+2 > len(t) {
		return 1
	}
	count := int(order.Uint16(t[ifd:]))
	for e := 0; e < count; e++ {
		at := ifd + 2 + e*12
		if at+12 > len(t) {
			return 1
		}
		if order.Uint16(t[at:]) == 0x0112 {
			if o := int(order.Uint16(t[at+8:])); o >= 1 && o <= 8 {
				return o
			}
			return 1
		}
	}
	return 1
}

// Orient turns img upright for EXIF orientation o.
func Orient(img image.Image, o int) image.Image {
	if o <= 1 || o > 8 {
		return img
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	ow, oh := w, h
	if o >= 5 { // 5 to 8 swap the sides
		ow, oh = h, w
	}
	out := image.NewNRGBA(image.Rect(0, 0, ow, oh))
	for y := 0; y < oh; y++ {
		for x := 0; x < ow; x++ {
			var sx, sy int
			switch o {
			case 2: // mirrored
				sx, sy = w-1-x, y
			case 3: // upside down
				sx, sy = w-1-x, h-1-y
			case 4: // mirrored upside down
				sx, sy = x, h-1-y
			case 5: // mirrored, turned left
				sx, sy = y, x
			case 6: // turned left: rotate 90° clockwise
				sx, sy = y, h-1-x
			case 7: // mirrored, turned right
				sx, sy = w-1-y, h-1-x
			case 8: // turned right: rotate 90° counterclockwise
				sx, sy = w-1-y, x
			}
			out.Set(x, y, img.At(b.Min.X+sx, b.Min.Y+sy))
		}
	}
	return out
}

// Fit shrinks img so its longest side is at most side, averaging the
// pixels each output pixel covers. Smaller images are returned as they are.
func Fit(img image.Image, side int) image.Image {
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	longest := max(w, h)
	if longest <= side {
		return img
	}
	ow, oh := max(w*side/longest, 1), max(h*side/longest, 1)
	out := image.NewNRGBA(image.Rect(0, 0, ow, oh))
	for y := 0; y < oh; y++ {
		y0, y1 := y*h/oh, max((y+1)*h/oh, y*h/oh+1)
		for x := 0; x < ow; x++ {
			x0, x1 := x*w/ow, max((x+1)*w/ow, x*w/ow+1)
			var r, g, bl, a, n uint64
			for sy := y0; sy < y1; sy++ {
				for sx := x0; sx < x1; sx++ {
					cr, cg, cb, ca := img.At(b.Min.X+sx, b.Min.Y+sy).RGBA()
					r, g, bl, a, n = r+uint64(cr), g+uint64(cg), bl+uint64(cb), a+uint64(ca), n+1
				}
			}
			i := out.PixOffset(x, y)
			out.Pix[i] = uint8(r / n >> 8)
			out.Pix[i+1] = uint8(g / n >> 8)
			out.Pix[i+2] = uint8(bl / n >> 8)
			out.Pix[i+3] = uint8(a / n >> 8)
		}
	}
	return out
}
