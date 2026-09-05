# Images and codecs

[[Pixel.Image]] is the center of the CPU image API. It owns its storage and carries
the geometry and [[Pixel.PixelFormat]] needed to interpret every row.

## Load, transform, save

The filename extension selects the decoder or encoder. Built-in decoding covers BMP,
DDS, EXR, GIF, ICO, JPEG, KTX2, PNG, PSD, QOI, TGA, TIFF, and WebP. Every format but
PSD also has a built-in encoder where the container has a useful flattened-image
writing contract.

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

## Read animations and image sets

[[Pixel.ImageReader]] owns its encoded input and exposes the container through
[[Pixel.ImageSetInfo]]. Its [[Pixel.ImageFrameInfo]] entries distinguish timed
animation frames from document pages, icon variants, raster layers, and texture
subresources. Reading an index returns an independently owned [[Pixel.Image]].

```swag
var reader = try ImageReader.load("animation.webp")
for index in reader.info.frames.count
{
    let description = &reader.info.frames[index]
    var image = try reader.read(cast(u32) index)
    // Animation clients display this canvas for description.durationSeconds.
}
```

| Container | Indexed images |
|---|---|
| GIF | Animation frames, with palettes, transparency, delays, disposal, and loops |
| PNG/APNG | Animation frames, including partial rectangles, alpha blending, and restore-previous disposal |
| WebP | VP8 and VP8L animation frames, alpha, frame rectangles, durations, and loops |
| TIFF | Pages in the linked directory chain, using the supported strip encodings |
| ICO/CUR | Every PNG or supported DIB entry; the largest entry is the representative |
| DDS/KTX2 | Mip levels, array layers, cube faces, and volume slices in supported pixel/block formats |
| OpenEXR | Scanline parts with supported RGB(A)/Y half/float channels and compression |
| PSD | The composite followed by nonempty raster layers; layer effects and mask rendering are not applied |
| Other registered codecs | One representative image, without an additional interface requirement |

Animation reads return complete canvases in `RGBA8`, or `RGBA16` for 16-bit PNG.
Frame rectangles use top-left coordinates. Encoded durations remain in seconds,
including zero for unspecified delays; clients choose their fallback duration.
The loop count means total plays, with zero for unlimited playback. GIF repeat
counts are converted to this convention. Forward reads reuse the canvas; backward
seeks replay the necessary frames. Pixels are not cached by the reader.

[[Pixel.Image.load]] and [[Pixel.Image.decode]] retain a still-image contract:
the first composited GIF/WebP frame, the PNG default image (which can be a separate
APNG poster), the first TIFF page or EXR part, the PSD composite, the largest icon
entry, or the base texture's first subresource. Unsupported compression, tiled EXR,
deep EXR, and unsupported channel layouts still fail explicitly.

[[Pixel.DecodeOptions]] bounds encoded bytes, indexed frames, pixels per image,
and decoded buffer size. The reader checks geometry before pixel allocation;
zero removes a particular limit. KTX2 supercompression also applies the byte limit
to the whole inflated level. `decodePixels: false` indexes and probes geometry
without allocating image pixels. Metadata remains optional and owned by the image.

User-registered decoder types can implement [[Pixel.IImageSetDecoder]] alongside
[[Pixel.IImageDecoder]]. The reader owns the bytes borrowed by `open`, keeps the
decoder at a stable address, and performs common animation compositing. `readFrame`
returns an uncomposited rectangle and must accept any indexed frame number.

## Choose a pixel format

Use [[Pixel.PixelFormat]] `RGBA8` for general-purpose color with alpha and `RGB8`
when opacity is guaranteed. `RGB16`/`RGBA16` retain normalized 16-bit samples;
the `F16` and `F32` families retain HDR values. Each precision also has compact
`Gray` and `GrayAlpha` storage for masks, distance fields, and luminance images.
Query [[Pixel.PixelFormat.bitsPerPixel]],
[[Pixel.PixelFormat.channels]], and [[Pixel.PixelFormat.hasAlpha]] when generic code
must adapt to the encoding.

All packed formats can be converted with [[Pixel.Image.convertTo]] or copied with
[[Pixel.Image.convertedTo]]. Converting to an integer format clamps and quantizes;
converting to grayscale uses luminance; adding alpha creates opaque samples; removing
alpha discards it. Floating-point conversions preserve finite HDR values until an
integer destination requires clamping.

Packed image and texture storage supports these precisions. Painter render targets remain
straight-alpha `RGBA8`; convert their readback explicitly when a high-precision processing
pipeline is required.

[[Pixel.AlphaMode]] records whether stored colors are straight or premultiplied.
Use [[Pixel.Image.convertAlphaTo]] when crossing an API boundary with a different
alpha convention. Filters and resampling preserve this association, and encoders
write straight-alpha file samples.

| Field | Meaning |
|---|---|
| `width`, `height` | Image extent in pixels |
| `rowStride` | Byte stride of one tightly packed row |
| `pixels` | Owned row-major bytes |
| `pixelFormat` | Encoding of each pixel |
| `alphaMode` | Straight or premultiplied alpha association |
| `metadata` | Codec metadata preserved when supported |

> WARNING: Low-level access through `pixels` must honor `pixelFormat`,
> `bytesPerPixel`, and `rowStride`.
> Prefer the typed image operations unless direct byte access is required.

## Codec precision

PNG preserves 8- and 16-bit grayscale or RGB samples with optional alpha. EXR
preserves half- and full-float Y, YA, RGB, and RGBA scanlines. DDS and KTX2 preserve
their supported uncompressed integer and floating layouts; their decoders also read
BC1 through BC5 block-compressed textures. Other general-purpose codecs convert to
the nearest supported 8-bit RGB/RGBA representation.

The PSD decoder imports the flattened composite from PSD version 1 RGB or grayscale files with
8- or 16-bit raw or PackBits channel data. An optional alpha channel is retained. Layers, masks,
CMYK/Lab color modes, effects, and PSB files are rejected instead of being silently flattened or
misinterpreted.

## Encoding options

Pass the encoder-specific options value as the second argument of
[[Pixel.Image.save]]. A null option value selects the encoder defaults. Decode
limits and requested output behavior belong in [[Pixel.DecodeOptions]] when loading
untrusted or unusually large files.
