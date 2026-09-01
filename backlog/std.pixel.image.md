# Pixel Image Backlog

This backlog covers image decoding, encoding, metadata, multi-image containers, and SVG input
owned by `bin/std/modules/pixel`. Module-wide rendering, effects, image transformations, surface,
texture-sampling, vector-output, and geometry work lives in [std.pixel.md](std.pixel.md).
Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in Git, not here.

## Where the image stack already stands

Thirteen decoders and twelve encoders cover BMP, DDS, EXR, GIF, ICO, JPEG including progressive
decode, KTX2, PNG, flattened PSD import, QOI, TGA, TIFF, and WebP with lossless and VP8 decode.
Grayscale, RGB, and RGBA storage spans 8-bit, normalized 16-bit, half-float, and full-float samples
with explicit straight or premultiplied alpha. Fifteen eager filters and twelve in-place transforms
include content-aware smart crop, typed precision conversion, alpha conversion, and Haar feature
statistics. The static SVG path covers shapes, reuse, viewports, clipping, markers, patterns, text,
raster images, CSS Color 3 paints, affine transforms, centered gradients, and a small filter chain.

The remaining gaps are color metadata, bounded and source-neutral input, multi-image containers,
complete texture delivery, and format breadth and fidelity.

## Tier A — Safe and source-neutral image input

### std.pixel.image.036 — Decoding has no shared resource limits

- Evidence: `DecodeOptions` can suppress pixels or metadata but cannot cap dimensions, decoded
  bytes, frame count, metadata bytes, work, or compression ratio. Most codecs accept any positive
  dimensions that fit `s32`, so a small untrusted file can request an allocation far beyond the
  caller's budget. The help text already promises decode limits that the type does not contain.
- Next: define format-neutral hard limits in `DecodeOptions`, apply them before allocation in every
  built-in decoder, and define whether a decoder may impose a stricter format limit.
- Complete when: one options value bounds geometry, decoded storage, metadata, and multi-frame work
  consistently across every built-in codec, with adversarial tests proving rejection before large
  allocation.

### std.pixel.image.037 — Codec selection trusts the filename extension

- Evidence: `ImageFormat.matches`, `Image.load`, and `Image.decode` choose a decoder from a suffix;
  a valid buffer without a name cannot be decoded, and a renamed file is sent to the wrong codec.
  Skia and libvips select buffer/source loaders by inspecting their signatures.
- Next: add a bounded probe contract to `IImageDecoder`, keep an explicit format hint as an
  optimization or disambiguator, and make the filename overload forward to content detection.
- Complete when: file, memory, and data-URI input decode correctly without a trustworthy extension,
  malformed and ambiguous signatures fail deterministically, and codec registration order does not
  silently change the selected format.
- Related: std.pixel.image.038

### std.pixel.image.038 — Codecs require one complete contiguous input buffer

- Evidence: `IImageDecoder.decode` takes `const [..] u8`; `Image.load` first reads the whole file;
  the incremental logic inside individual codecs is not exposed through the format-neutral API.
  Skia distinguishes incremental and scanline decode, while libvips loaders accept abstract
  sources and sequential access.
- Next: define a seekable/sequential image source contract and decoder lifecycle without making
  every codec pretend it can seek or resume.
- Complete when: a caller can probe and decode from file, memory, or a bounded sequential source;
  incremental-capable codecs report incomplete input without losing state; codecs that require
  random access state that requirement explicitly.
- Related: std.pixel.image.037, std.pixel.image.039, std.pixel.019

### std.pixel.image.039 — Decode cannot request a subset or native scale

- Evidence: `DecodeOptions` only selects pixels and metadata. A thumbnail caller must decode the
  full image and resize it, and a large tiled or multi-resolution source cannot expose one region
  without materializing the base image. Skia codecs expose subset and supported-scale contracts;
  OpenEXR and KTX2 have addressable tiles or levels.
- Next: define requested output size, source rectangle, and orientation behavior as decoder
  capabilities with a documented fallback path.
- Complete when: a caller can request a bounded thumbnail or region, determine whether the codec
  honored it natively, and receive the same pixels as the defined full-decode fallback within the
  stated resampling tolerance.
- Related: std.pixel.image.038, std.pixel.image.041, std.pixel.019

### std.pixel.image.044 — Orientation and common metadata have no typed contract

- Evidence: `ImageMetadata` preserves opaque byte records, but callers cannot ask for normalized
  EXIF orientation, pixel density, capture time, textual fields, ICC identity, or a thumbnail.
  Loading a camera image therefore does not say whether its pixel rows are already display-ready.
- Next: separate normalized cross-format properties from preserved opaque records, beginning with
  encoded orientation and density, and decide whether load applies orientation or only reports it.
- Complete when: JPEG, PNG, WebP, and TIFF fixtures expose the same normalized property vocabulary,
  unknown metadata still round-trips where supported, and orientation is applied exactly once.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.image.037

---

---

## Tier A — SVG input fidelity

### std.pixel.image.008 — Radial gradients lose their focus and elliptical space

- Evidence: the parser reads `fx`, `fy`, and `fr`, but `Brush` carries only one center and scalar
  radii. Object-bounding-box gradients over non-square bounds are consequently sampled as circles.
- Next: give the brush a focus point and gradient-space transform, then implement the two-point
  conical equation in both samplers.
- Complete when: focal and focal-radius fixtures match browser rendering, a wide
  object-bounding-box radial is elliptical, and CPU/OpenGL parity covers inside, edge, and
  out-of-circle focal points.
- Related: std.pixel.image.010, std.pixel.001

### std.pixel.image.010 — SVG masks are not parsed

- Evidence: clipping supplies binary geometry coverage, but SVG masks require a rendered alpha or
  luminance image. `Layer` and `DstIn` provide most of the composition path, yet no resolve turns
  mask luminance into the alpha consumed by `DstIn`.
- Next: land `mask-type="alpha"` over layer alpha first, then add luminance-to-alpha resolve and
  parse `mask`, `maskUnits`, and `maskContentUnits`.
- Complete when: alpha and luminance masks honor their coordinate systems, black hides, white
  reveals, gradients fade continuously, unresolved references leave content unmasked, and both
  renderers agree.
- Related: std.pixel.image.008, std.pixel.018

---

## Tier A — Image color metadata

### std.pixel.image.019 — Embedded ICC profiles are preserved but not interpreted

- Evidence: PNG `iCCP` and JPEG application records can survive as opaque metadata, but Pixel
  cannot validate a profile, derive a color space from it, or convert pixels through it.
- Next: choose the supported matrix/TRC and LUT profile classes, define invalid-profile behavior,
  and integrate conversion with the std.pixel.001 color-space object.
- Complete when: embedded sRGB, Display P3, grayscale, and one LUT-profile fixture convert to a
  declared destination with reference tolerances, while unsupported profiles are reported without
  discarding their bytes.
- Related: std.pixel.001, std.pixel.002, std.pixel.image.044

---

## Tier B — Multi-image and bounded processing

### std.pixel.image.040 — Multi-frame decoding is GIF-specific

- Evidence: `Gif.Decoder` exposes sequential `nextFrame`, `frameCount`, and `rewind`, but
  `IImageDecoder` can return only one `Image`. APNG and animated WebP are explicitly rejected, GIF
  encoding writes one frame, and TIFF/ICO/EXR secondary images have no common model.
- Next: define a format-neutral decoder/image-set contract for canvas, frame rectangle, duration,
  disposal, blend, loop count, random versus sequential access, and still-image fallback; migrate
  GIF before adding another animated codec.
- Complete when: the generic API can drive GIF and at least APNG or animated WebP without
  format-specific casts, preserves timing/disposal semantics, enforces std.pixel.image.036 limits, and
  still-image callers receive the documented representative frame.
- Related: std.pixel.image.026, std.pixel.image.027, std.pixel.image.036, std.pixel.image.038

## Tier B — Image and texture codecs

### std.pixel.image.026 — No AVIF codec

- Evidence: AVIF 1.2 covers SDR, HDR/WCG, alpha, image sequences, progressive layers, auxiliary
  depth, and tone-map derived images. Treating it as an 8-bit still codec would immediately create
  debt across color and animation.
- Next: choose an AV1/HEIF dependency and first supported profile, then land still decode/encode
  with explicit bit-depth, YUV, alpha, color, metadata, and limit behavior.
- Complete when: 8/10/12-bit still fixtures with and without alpha decode and round-trip within
  codec tolerance, malformed containers obey shared limits, and unsupported sequence/HDR features
  are reported rather than silently flattened.
- Related: std.pixel.001, std.pixel.003, std.pixel.image.036, std.pixel.image.040

### std.pixel.image.027 — No JPEG XL codec

- Evidence: JPEG XL combines lossy and lossless coding with alpha, animation, layers, thumbnails,
  progressive decode, metadata, and lossless JPEG reconstruction. Its contract is independent of
  AVIF even when both use the same color and animation abstractions.
- Next: choose a dependency and a still-image v1 profile, including whether legacy-JPEG
  reconstruction bytes are preserved.
- Complete when: lossy and lossless still fixtures across supported precision and alpha decode and
  encode, color metadata reaches std.pixel.001, and unsupported animation/layer features fail
  explicitly.
- Related: std.pixel.001, std.pixel.image.036, std.pixel.image.040

### std.pixel.image.041 — DDS and KTX2 are flattened to one base-level image

- Evidence: both decoders now exist, but each returns the base level's first layer and face as one
  `Image`. The public model cannot retain mip levels, array layers, cubemap faces, volume slices,
  per-level metadata, or the container's original block payload.
- Next: define a texture-source value distinct from `Image`, with indexed levels/layers/faces,
  dimensions, format/color metadata, borrowed versus owned payloads, and explicit selection APIs;
  migrate KTX2 before extending DDS.
- Complete when: a mipmapped cubemap array can be inspected and one subresource decoded without
  flattening the rest, while ordinary `Image.load` retains its documented base-image fallback.
- Related: std.pixel.image.039, std.pixel.image.042, platform.portability.066

### std.pixel.image.042 — GPU-compressed texture data cannot reach the GPU compressed

- Evidence: BC1 through BC5 are decoded to RGBA8; KTX2 BasisLZ, Zstandard, ETC, ASTC, BC6H, and BC7
  are unsupported; `IRenderer.addImage` accepts only decoded `Image` or YUV420. KTX2 is designed for
  per-level streaming and Basis Universal transcoding to a GPU-native block format.
- Next: add compressed-format capability queries and texture upload from std.pixel.image.041, then
  choose native block families and a Basis Universal transcoder from the target matrix.
- Complete when: a KTX2 Basis or supported native-block fixture uploads without an RGBA expansion,
  chooses a supported target deterministically, preserves mip levels, and has an explicit CPU
  fallback.
- Related: std.pixel.image.041, std.pixel.004, platform.portability.066

### std.pixel.image.047 — WebP encoding is lossless-only

- Evidence: WebP decode covers VP8 and VP8L, but the encoder writes only VP8L. A caller cannot make
  the ordinary quality/size tradeoff for photographic WebP output despite the module already
  understanding the lossy bitstream on input.
- Next: define lossy encoder options for quality, alpha quality, chroma, method, and metadata, then
  implement or adopt a VP8 still encoder independently of animation.
- Complete when: opaque and alpha photographic fixtures encode at bounded quality settings,
  metadata behavior is explicit, and decoded distortion/size regressions are measured.
- Related: std.pixel.001, std.pixel.image.040

### std.pixel.image.048 — JPEG encoding cannot produce progressive output

- Evidence: JPEG decode handles baseline and progressive scans, but encoding is baseline-only.
  Progressive delivery remains a common web/export requirement and exercises a different scan and
  Huffman contract rather than a flag on the current writer.
- Next: define a scan script and coefficient lifetime for progressive Huffman encoding, reusing the
  existing DCT and metadata writer.
- Complete when: grayscale and RGB fixtures encode with multiple valid scans, decode identically to
  their baseline equivalents within JPEG tolerance, and malformed scan plans are rejected.

### std.pixel.image.049 — OpenEXR PIZ compression is not decoded

- Evidence: decode accepts single-part RGB/RGBA/Y scanlines with none, ZIPS, or ZIP compression;
  encode is uncompressed. OpenEXR identifies PIZ as its wavelet/Huffman lossless option, and files
  using it are rejected before the otherwise supported half/float channels can be reconstructed.
- Next: implement PIZ decode for the existing scanline RGB(A)/Y contract and validate it against
  the reference library before deciding whether PIZ encoding is justified.
- Complete when: half and float PIZ scanline fixtures decode to reference pixels, malformed wavelet
  and Huffman data fail within std.pixel.image.036 limits, and unsupported channel layouts still fail
  explicitly.
- Related: std.pixel.image.036, std.pixel.image.050

### std.pixel.image.050 — Tiled and multi-resolution OpenEXR images are rejected

- Evidence: OpenEXR tiles provide random rectangular access and can carry mipmap or ripmap levels,
  but Pixel accepts scanline images only. This blocks native region/scale decode even when the file
  already contains the needed subdivision and resolution.
- Next: expose tiled single-part RGB(A)/Y input through the region and subresource contracts from
  std.pixel.image.039 and std.pixel.image.041, including one-level, mipmap, and ripmap indexing.
- Complete when: callers can inspect levels and decode a selected tile or bounded region without
  materializing the base image, with reference fixtures for incomplete edge tiles and both level
  rounding modes.
- Related: std.pixel.image.039, std.pixel.image.041, std.pixel.019, std.pixel.image.049

---

## Out of scope

**Rendering, effects, transformations, surfaces, and geometry.** The module-wide color contract,
image-effect graph, bounded transformation pipeline, texture sampling, painter output, and path
operations live in [std.pixel.md](std.pixel.md).

**Text shaping and font-format completion.** Pixel consumes positioned glyphs, but GSUB/GPOS
shaping, variable fonts, and color-glyph formats are tracked in
[std.truetype.md](std.truetype.md).

**Deep EXR samples, editable PSD layers, and a general document-layer model.** These are not one
flat `Image`. Add a specialized image-set or document contract only when a named application needs
to preserve and edit them; do not silently flatten them and call the format complete.

**Video decoding.** WebP VP8 exists because WebP needs it, and YUV420 exists to hand decoded planes
to a renderer. A timed media pipeline belongs in `std/video`.
