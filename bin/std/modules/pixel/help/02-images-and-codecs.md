# Images and codecs

[[Pixel.Image]] is the center of the CPU image API. It owns its storage and carries
the geometry and [[Pixel.PixelFormat]] needed to interpret every row.

## Load, transform, save

The filename extension selects the decoder or encoder. Keep the image in a format
supported by the operation you call; conversion methods document any stricter
requirements.

```swag
using Pixel

var image = try Image.load("portrait.png")
image.crop(40, 20, 640, 640)
image.resize(256, 256, .Bilinear)
try image.save("avatar.png")
```

`crop`, `resize`, `flip`, filters, and channel operations mutate the image. This
makes a processing pipeline read naturally and avoids a chain of short-lived image
values.

## Choose a pixel format

Use [[Pixel.PixelFormat]] `RGBA8` for general-purpose color with alpha and `RGB8`
when opacity is guaranteed. Grayscale formats are useful
for masks and image analysis. Query [[Pixel.PixelFormat.bpp]],
[[Pixel.PixelFormat.channels]], and [[Pixel.PixelFormat.hasAlpha]] when generic code
must adapt to the encoding.

| Field | Meaning |
|---|---|
| `width`, `height` | Image extent in pixels |
| `width8` | Byte stride of one tightly packed row |
| `pixels` | Owned row-major bytes |
| `metaDatas` | Codec metadata preserved when supported |

> WARNING: Low-level access through `pixels` must honor `pf`, `bpp8`, and `width8`.
> Prefer the typed image operations unless direct byte access is required.

## Encoding options

Pass the encoder-specific options value as the second argument of
[[Pixel.Image.save]]. A null option value selects the encoder defaults. Decode
limits and requested output behavior belong in [[Pixel.DecodeOptions]] when loading
untrusted or unusually large files.
