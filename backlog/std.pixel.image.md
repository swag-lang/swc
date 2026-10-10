# Pixel Image Backlog

This backlog covers image decoding, encoding, metadata, multi-image containers, and SVG input
owned by `bin/std/modules/pixel`. Module-wide rendering, effects, image transformations, surface,
texture-sampling, vector-output, and geometry work lives in [std.pixel.md](std.pixel.md).
Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). [README.md](README.md) has the whole layout.

Entries stay in one flat list. Delete an entry when it
ships; history lives in Git, not here.

## Entries

### std.pixel.image.038 — Codecs require one complete contiguous input buffer

- Evidence: `IImageDecoder.decode` takes `const [..] u8`; `Image.load` maps the whole file and
  hands one contiguous slice to the decoder (`image/decode/decode.swg`); the incremental logic inside individual codecs is not exposed through the format-neutral API.
  Skia distinguishes incremental and scanline decode, while libvips loaders accept abstract
  sources and sequential access.
- Next: define a seekable/sequential image source contract and decoder lifecycle without making
  every codec pretend it can seek or resume.
- Done when: a caller can probe and decode from file, memory, or a bounded sequential source;
  incremental-capable codecs report incomplete input without losing state; codecs that require
  random access state that requirement explicitly.
- Related: std.pixel.image.037, std.pixel.image.039, std.pixel.019

### std.pixel.image.037 — Automatic codec selection trusts the filename extension

- Evidence: `ImageFormat.matches`, `Image.load`, and the filename overload of `Image.decode`
  choose a decoder from a suffix, so a renamed file is sent to the wrong codec. The explicit
  `Image.decode(decoderType, bytes)` overload accepts unnamed input when the caller already knows
  its decoder; no format-neutral content probe makes that choice.
  Skia and libvips select buffer/source loaders by inspecting their signatures.
- Next: add a bounded probe contract to `IImageDecoder`, keep an explicit format hint as an
  optimization or disambiguator, and make the filename overload forward to content detection.
- Done when: file, memory, and data-URI input decode correctly without a trustworthy extension,
  malformed and ambiguous signatures fail deterministically, and codec registration order does not
  silently change the selected format.
- Related: std.pixel.image.038

### std.pixel.image.008 — Radial gradients lose their focus and elliptical space

- Evidence: the parser reads `fx`, `fy`, and `fr`, but resolves radial paints with equal
  `gradientStart` and `gradientEnd`. The radial sampler uses only `gradientStart` and scalar radii. Object-bounding-box gradients over non-square bounds are consequently sampled as circles.
- Next: define distinct focus/center semantics for the existing gradient endpoints and add a
  gradient-space transform, then implement the two-point
  conical equation in both samplers.
- Done when: focal and focal-radius fixtures match browser rendering, a wide
  object-bounding-box radial is elliptical, and CPU/OpenGL parity covers inside, edge, and
  out-of-circle focal points.
- Related: std.pixel.image.010, std.pixel.001

### std.pixel.image.042 — GPU-compressed texture data cannot reach the GPU compressed

- Evidence: BC1 through BC5 are decoded to RGBA8; KTX2 BasisLZ, Zstandard, ETC, ASTC, BC6H, and BC7
  are unsupported; `IRenderer.addImage` accepts decoded `Image` or a planar `YuvPlanarView` (4:2:0 or 4:4:4). KTX2 is designed for
  per-level streaming and Basis Universal transcoding to a GPU-native block format.
- Next: add compressed-format capability queries and texture upload from std.pixel.image.041, then
  choose native block families and a Basis Universal transcoder from the target matrix.
- Done when: a KTX2 Basis or supported native-block fixture uploads without an RGBA expansion,
  chooses a supported target deterministically, preserves mip levels, and has an explicit CPU
  fallback.
- Related: std.pixel.image.041, std.pixel.004, platform.portability.066

### std.pixel.image.036 — Decoding has no cumulative resource budget

- Evidence: `DecodeOptions` now bounds encoded bytes, frame count, pixels per image/canvas, and
  bytes per pixel buffer. `image.imagereader.test.swg` protects these limits, including cyclic TIFF
  indexes and oversized DDS arrays. Those ceilings do not account for the aggregate live storage
  of encoded bytes, indexes, metadata, animation canvases, saved disposal frames, and decoder
  scratch buffers; no shared budget follows that storage through a decode.
- Next: define a cumulative allocation budget carried by the reader and its decoder, retaining the
  existing per-image limits and accounting for temporary as well as retained storage.
- Done when: every built-in decoder reserves against that budget before allocating, releases
  its charge with the storage, and adversarial multi-image and metadata fixtures prove that several
  individually legal buffers cannot exceed the caller's total limit.

### std.pixel.image.039 — Decode cannot request a subset or native scale

- Evidence: `DecodeOptions` selects pixels, metadata, and resource ceilings, but no source rectangle
  or requested scale. `ImageReader` can select an existing DDS/KTX2 level without decoding the
  base image; it cannot ask a decoder to produce an arbitrary thumbnail or crop. A caller must
  decode the selected image and transform it afterwards.
- Next: define requested output size, source rectangle, and orientation behavior as decoder
  capabilities with a documented fallback path.
- Done when: a caller can request a bounded thumbnail or region, determine whether the codec
  honored it natively, and receive the same pixels as the defined full-decode fallback within the
  stated resampling tolerance.
- Related: std.pixel.image.038, std.pixel.019

### std.pixel.image.026 — No AVIF codec

- Evidence: AVIF 1.2 covers SDR, HDR/WCG, alpha, image sequences, progressive layers, auxiliary
  depth, and tone-map derived images. Treating it as an 8-bit still codec would immediately create
  debt across color and animation.
- Next: choose an AV1/HEIF dependency and first supported profile, then land still decode/encode
  with explicit bit-depth, YUV, alpha, color, metadata, and limit behavior.
- Done when: 8/10/12-bit still fixtures with and without alpha decode and round-trip within
  codec tolerance, malformed containers obey shared limits, and unsupported sequence/HDR features
  are reported rather than silently flattened.
- Related: std.pixel.001, std.pixel.003, std.pixel.image.036

### std.pixel.image.027 — No JPEG XL codec

- Evidence: JPEG XL combines lossy and lossless coding with alpha, animation, layers, thumbnails,
  progressive decode, metadata, and lossless JPEG reconstruction. Its contract is independent of
  AVIF even when both use the same color and animation abstractions.
- Next: choose a dependency and a still-image v1 profile, including whether legacy-JPEG
  reconstruction bytes are preserved.
- Done when: lossy and lossless still fixtures across supported precision and alpha decode and
  encode, color metadata reaches std.pixel.001, and unsupported animation/layer features fail
  explicitly.
- Related: std.pixel.001, std.pixel.image.036

### std.pixel.image.041 — Texture subresources cannot expose their encoded block payload

- Evidence: `ImageReader` now indexes DDS/KTX2 mip levels, array layers, cubemap faces, and volume
  slices; array, cube, volume, and zlib-KTX2 fixtures cover independent reads. Its public read still
  returns decoded pixels. The original compressed block format and payload cannot be obtained for
  one indexed subresource without reparsing the container outside the reader.
- Next: expose a texture subresource's encoded format, dimensions, color metadata, and block bytes
  with an explicit lifetime contract, reusing the existing index.
- Done when: a caller can retain or borrow a selected subresource's original block payload
  without an RGBA expansion, while `ImageReader.read` and `Image.load` keep their pixel contracts.
- Related: std.pixel.image.042, platform.portability.066

### std.pixel.image.047 — WebP encoding is lossless-only

- Evidence: WebP decode covers VP8 and VP8L, but the encoder writes only VP8L. A caller cannot make
  the ordinary quality/size tradeoff for photographic WebP output despite the module already
  understanding the lossy bitstream on input.
- Next: define lossy encoder options for quality, alpha quality, chroma, method, and metadata, then
  implement or adopt a VP8 still encoder independently of animation.
- Done when: opaque and alpha photographic fixtures encode at bounded quality settings,
  metadata behavior is explicit, and decoded distortion/size regressions are measured.
- Related: std.pixel.001

### std.pixel.image.049 — OpenEXR PIZ compression is not decoded

- Evidence: decode accepts single- and multipart RGB/RGBA/Y scanlines with none, ZIPS, or ZIP compression;
  encode is uncompressed. OpenEXR identifies PIZ as its wavelet/Huffman lossless option, and files
  using it are rejected before the otherwise supported half/float channels can be reconstructed.
- Next: implement PIZ decode for the existing scanline RGB(A)/Y contract and validate it against
  the reference library before deciding whether PIZ encoding is justified.
- Done when: half and float PIZ scanline fixtures decode to reference pixels, malformed wavelet
  and Huffman data fail within std.pixel.image.036 limits, and unsupported channel layouts still fail
  explicitly.
- Related: std.pixel.image.036, std.pixel.image.050

### std.pixel.image.050 — Tiled and multi-resolution OpenEXR images are rejected

- Evidence: OpenEXR tiles provide random rectangular access and can carry mipmap or ripmap levels,
  but Pixel accepts scanline images only. This blocks native region/scale decode even when the file
  already contains the needed subdivision and resolution.
- Next: extend `ImageReader`'s index to tiled RGB(A)/Y input and the region contract from
  std.pixel.image.039, including one-level, mipmap, and ripmap indexing.
- Done when: callers can inspect levels and decode a selected tile or bounded region without
  materializing the base image, with reference fixtures for incomplete edge tiles and both level
  rounding modes.
- Related: std.pixel.image.039, std.pixel.019, std.pixel.image.049

### std.pixel.image.044 — Orientation and common metadata have no typed contract

- Evidence: `ImageMetadata` preserves opaque byte records and `Exif.decode` provides readable TIFF,
  photo, and GPS fields, but callers cannot ask for normalized
  EXIF orientation, pixel density, capture time, textual fields, ICC identity, or a thumbnail.
  Loading a camera image therefore does not say whether its pixel rows are already display-ready.
- Next: separate normalized cross-format properties from preserved opaque records, beginning with
  encoded orientation and density, and decide whether load applies orientation or only reports it.
- Done when: JPEG, PNG, WebP, and TIFF fixtures expose the same normalized property vocabulary,
  unknown metadata still round-trips where supported, and orientation is applied exactly once.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.image.037

### std.pixel.image.010 — SVG masks are not parsed

- Evidence: clipping supplies binary geometry coverage, but SVG masks require a rendered alpha or
  luminance image. `Layer` and `DstIn` provide most of the composition path, yet no resolve turns
  mask luminance into the alpha consumed by `DstIn`.
- Next: land `mask-type="alpha"` over layer alpha first, then add luminance-to-alpha resolve and
  parse `mask`, `maskUnits`, and `maskContentUnits`.
- Done when: alpha and luminance masks honor their coordinate systems, black hides, white
  reveals, gradients fade continuously, unresolved references leave content unmasked, and both
  renderers agree.
- Related: std.pixel.image.008, std.pixel.018

### std.pixel.image.019 — Embedded ICC profiles are preserved but not interpreted

- Evidence: PNG `iCCP` and JPEG application records can survive as opaque metadata, but Pixel
  cannot validate a profile, derive a color space from it, or convert pixels through it.
- Next: choose the supported matrix/TRC and LUT profile classes, define invalid-profile behavior,
  and integrate conversion with the std.pixel.001 color-space object.
- Done when: embedded sRGB, Display P3, grayscale, and one LUT-profile fixture convert to a
  declared destination with reference tolerances, while unsupported profiles are reported without
  discarding their bytes.
- Related: std.pixel.001, std.pixel.002, std.pixel.image.044

### std.pixel.image.048 — JPEG encoding cannot produce progressive output

- Evidence: JPEG decode handles baseline and progressive scans, but encoding is baseline-only.
  Progressive delivery remains a common web/export requirement and exercises a different scan and
  Huffman contract rather than a flag on the current writer.
- Next: define a scan script and coefficient lifetime for progressive Huffman encoding, reusing the
  existing DCT and metadata writer.
- Done when: grayscale and RGB fixtures encode with multiple valid scans, decode identically to
  their baseline equivalents within JPEG tolerance, and malformed scan plans are rejected.

---
