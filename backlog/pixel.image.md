# Pixel Backlog

This backlog covers `std/pixel`, measured against the 2D rendering contract of Skia, Direct2D,
Blend2D, Cairo, and ThorVG, and against Skia Codec and libvips for image processing. Format-specific
coverage is measured against the current PNG, WebP, AVIF, JPEG XL, KTX2, and OpenEXR specifications,
not against the mere presence of a filename extension.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/pixel` stay together
here. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). Font parsing and shaping belong in
[font.truetype.md](font.truetype.md). Platform renderer selection belongs in
[platform.portability.md](platform.portability.md). [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

This is one of the broadest modules in the tree, and several parts are unusual strengths.

- **Codecs:** thirteen decoders and twelve encoders cover BMP, DDS, EXR, GIF, ICO, JPEG including
  progressive decode, KTX2, PNG, flattened PSD import, QOI, TGA, TIFF, and WebP with lossless and
  VP8 decode. DDS and KTX2 are implemented; their remaining gap is the texture model, not format
  recognition.
- **Pixel storage:** grayscale, RGB, and RGBA storage spans 8-bit, normalized 16-bit, half-float,
  and full-float samples, with explicit straight or premultiplied alpha. This is already enough to
  carry HDR values through CPU image transforms even though rendering and display do not yet honor
  an HDR color contract.
- **Computational geometry:** `poly/` has boolean polygon operations, offsetting, and Delaunay
  triangulation, beside the painter's fill and stroke tessellation.
- **Math typesetting:** `math/expression.swg` and `math/layout.swg` implement TeX-style formula
  layout with display, text, script, and script-script styles. No compared general-purpose 2D
  renderer integrates this as a native family.
- **Distance-field text:** the `truetype` path generates both SDF and MSDF glyphs, which is the form
  GPU text wants.
- **Imaging:** fifteen eager image filters and twelve in-place transforms include content-aware
  `smartcrop`, typed precision conversion, alpha conversion, and Haar feature statistics.
- **Painter:** a full state stack, affine transforms, clipping rectangles and boolean clipping
  regions, render targets, layers, artistic blend modes, custom OpenGL shaders, and integrated DPI
  content scale.
- **Rendering:** deterministic CPU and OpenGL backends execute one recorded command stream, with
  command goldens and CPU/OpenGL image-parity tests.
- **SVG:** the parser handles the static artwork core: paths and shapes, definitions and reuse,
  viewports, clipping, markers, patterns, text, raster images, CSS Color 3 paints, affine
  transforms, centered gradients, and a small blur/offset/drop-shadow filter chain.

The important gaps are no longer basic shape or still-image coverage. They are effect composition,
color semantics, bounded and source-neutral image I/O, multi-image containers, complete texture
delivery, high-quality sampling, and a modern GPU path.

## State-of-the-art comparison

This table is the review boundary. It records an externally demonstrated contract, Pixel's current
position, and the backlog entry that owns the difference. It is deliberately not a catalogue of
every operation shipped by ImageMagick or every SVG element ever standardized.

| Family | Current external baseline | Pixel today | Gap owner |
| --- | --- | --- | --- |
| Effect composition | Skia image filters form a DAG with recursive bounds; Direct2D ships color, composition, blur, convolution, morphology, displacement, lighting, and HDR effects | Layers can blur and build a shadow; SVG owns an ad hoc linear filter subset; there is no public graph | pixel.image.002 through pixel.image.007, pixel.image.045 |
| Color | A Skia image carries alpha type and color space; Direct2D exposes color management, FP16 advanced-color rendering, and HDR tone mapping | Pixel carries precision and alpha association but no primaries, transfer function, ICC conversion, surface space, or luminance contract | pixel.image.018 through pixel.image.021 |
| Codec discovery and input | Skia codecs inspect encoded data and can decode incrementally, by scanline, by subset, or at a supported scale; libvips accepts abstract sources | The registry selects only by filename extension and every generic decoder receives one complete memory slice | pixel.image.036 through pixel.image.039 |
| Large-image processing | libvips evaluates requested regions on demand, joins operations without materializing intermediates, caches tiles, and streams sinks | Every transform mutates a fully materialized `Image`; every result must fit in memory | pixel.image.043 |
| Animation and image sets | Skia exposes format-neutral frame metadata; PNG 3, WebP, AVIF, JPEG XL, TIFF, and EXR all model more than one image in some form | Only the concrete GIF decoder iterates frames; generic loading returns one image | pixel.image.040 |
| Metadata and orientation | Modern codec APIs expose encoded origin and structured color/EXIF data while preserving unknown payloads | JPEG and PNG preserve selected opaque records, but callers have no normalized orientation or typed metadata view | pixel.image.044 |
| Web image formats | AVIF specifies HDR/WCG, alpha, image sequences, and progressive layers; JPEG XL specifies alpha, animation, layers, thumbnails, and progressive/lossless coding | Neither format is recognized | pixel.image.026, pixel.image.027 |
| Texture containers | KTX2 carries mip levels, array layers, faces, 3D slices, GPU blocks, Basis Universal, and per-level supercompression | DDS/KTX2 decode the base level's first 2D image; BC1-BC5 are expanded to RGBA8 before upload | pixel.image.041, pixel.image.042 |
| Texture sampling | Mature 2D GPU APIs distinguish nearest, linear, cubic, mipmapped, and often anisotropic sampling | Painter textures expose only `Pixel` and `Linear`; ordinary images have no mip chain | pixel.image.046 |
| GPU architecture | Skia Graphite targets Metal, Vulkan, and D3D12 through a multithreaded recorder model; Chrome uses WebGPU/Dawn as its portability layer | Pixel has CPU and a GL-centric backend; backend selection and target coverage are not decided | platform.portability.066 |
| Vector output | Cairo exports PDF, SVG, and PostScript; Skia exports PDF while preserving vector operations where possible | Pixel can serialize a narrow `Svg.Document`, but cannot export an arbitrary painter recording | pixel.image.022 through pixel.image.024 |
| Path utilities | Skia exposes path measurement and composable path effects | Pixel can dash and flatten paths, but cannot publicly measure, trim, round corners, or bridge painter paths to `poly/` | pixel.image.032 through pixel.image.035 |

Primary comparison sources:

- [Skia `SkImageFilter`](https://api.skia.org/classSkImageFilter.html),
  [`SkImageFilters`](https://api.skia.org/classSkImageFilters.html),
  [`SkImage`](https://api.skia.org/classSkImage.html), and
  [`SkCodec`](https://github.com/google/skia/blob/main/include/codec/SkCodec.h).
- [Direct2D built-in effects](https://learn.microsoft.com/en-us/windows/win32/direct2d/built-in-effects)
  and [advanced-color image rendering](https://learn.microsoft.com/en-us/samples/microsoft/windows-universal-samples/d2dadvancedcolorimages/).
- [libvips demand-driven evaluation](https://www.libvips.org/API/current/how-it-works.html).
- [PNG Third Edition](https://www.w3.org/TR/png-3/),
  [WebP container](https://developers.google.com/speed/webp/docs/riff_container),
  [AVIF 1.2](https://aomediacodec.github.io/av1-avif/v1.2.0.html), and
  [JPEG XL](https://jpeg.org/jpegxl/index.html).
- [KTX2 specification](https://github.khronos.org/KTX-Specification/ktxspec.v2.html) and
  [OpenEXR technical introduction](https://openexr.com/en/latest/TechnicalIntroduction.html).
- [Skia Graphite in Chrome](https://blog.google/chromium/introducing-skia-graphite-chromes/).

---

## Tier A — Safe and source-neutral image input

### pixel.image.036 — Decoding has no shared resource limits

- Evidence: `DecodeOptions` can suppress pixels or metadata but cannot cap dimensions, decoded
  bytes, frame count, metadata bytes, work, or compression ratio. Most codecs accept any positive
  dimensions that fit `s32`, so a small untrusted file can request an allocation far beyond the
  caller's budget. The help text already promises decode limits that the type does not contain.
- Next: define format-neutral hard limits in `DecodeOptions`, apply them before allocation in every
  built-in decoder, and define whether a decoder may impose a stricter format limit.
- Complete when: one options value bounds geometry, decoded storage, metadata, and multi-frame work
  consistently across every built-in codec, with adversarial tests proving rejection before large
  allocation.

### pixel.image.037 — Codec selection trusts the filename extension

- Evidence: `ImageFormat.matches`, `Image.load`, and `Image.decode` choose a decoder from a suffix;
  a valid buffer without a name cannot be decoded, and a renamed file is sent to the wrong codec.
  Skia and libvips select buffer/source loaders by inspecting their signatures.
- Next: add a bounded probe contract to `IImageDecoder`, keep an explicit format hint as an
  optimization or disambiguator, and make the filename overload forward to content detection.
- Complete when: file, memory, and data-URI input decode correctly without a trustworthy extension,
  malformed and ambiguous signatures fail deterministically, and codec registration order does not
  silently change the selected format.
- Related: pixel.image.038

### pixel.image.038 — Codecs require one complete contiguous input buffer

- Evidence: `IImageDecoder.decode` takes `const [..] u8`; `Image.load` first reads the whole file;
  the incremental logic inside individual codecs is not exposed through the format-neutral API.
  Skia distinguishes incremental and scanline decode, while libvips loaders accept abstract
  sources and sequential access.
- Next: define a seekable/sequential image source contract and decoder lifecycle without making
  every codec pretend it can seek or resume.
- Complete when: a caller can probe and decode from file, memory, or a bounded sequential source;
  incremental-capable codecs report incomplete input without losing state; codecs that require
  random access state that requirement explicitly.
- Related: pixel.image.037, pixel.image.039, pixel.image.043

### pixel.image.039 — Decode cannot request a subset or native scale

- Evidence: `DecodeOptions` only selects pixels and metadata. A thumbnail caller must decode the
  full image and resize it, and a large tiled or multi-resolution source cannot expose one region
  without materializing the base image. Skia codecs expose subset and supported-scale contracts;
  OpenEXR and KTX2 have addressable tiles or levels.
- Next: define requested output size, source rectangle, and orientation behavior as decoder
  capabilities with a documented fallback path.
- Complete when: a caller can request a bounded thumbnail or region, determine whether the codec
  honored it natively, and receive the same pixels as the defined full-decode fallback within the
  stated resampling tolerance.
- Related: pixel.image.038, pixel.image.041, pixel.image.043

### pixel.image.044 — Orientation and common metadata have no typed contract

- Evidence: `ImageMetadata` preserves opaque byte records, but callers cannot ask for normalized
  EXIF orientation, pixel density, capture time, textual fields, ICC identity, or a thumbnail.
  Loading a camera image therefore does not say whether its pixel rows are already display-ready.
- Next: separate normalized cross-format properties from preserved opaque records, beginning with
  encoded orientation and density, and decide whether load applies orientation or only reports it.
- Complete when: JPEG, PNG, WebP, and TIFF fixtures expose the same normalized property vocabulary,
  unknown metadata still round-trips where supported, and orientation is applied exactly once.
- Related: pixel.image.018, pixel.image.019, pixel.image.037

---

## Tier A — Composable image effects

### pixel.image.002 — No public image-filter graph

- Evidence: blur and shadow are layer operations, and SVG evaluates a private linear subset. There
  is no public DAG that applies effects to rendered content, shares an intermediate, or feeds one
  result to several consumers. Skia's filter contract recursively maps bounds through a DAG.
- Next: define graph inputs, immutable node ownership, bounds propagation, evaluation, temporary
  target lifetime, caching, color-space transitions, and backend fallback independently of the
  concrete node catalogue.
- Complete when: one graph can branch and rejoin, evaluates identically on CPU and GPU, allocates
  only propagated bounds, reuses unchanged intermediates, and cannot retain a dead render target.
- Related: pixel.image.003, pixel.image.004, pixel.image.005, pixel.image.006, pixel.image.007,
  pixel.image.018, pixel.image.045

### pixel.image.003 — No composable blur effect node

- Evidence: `Layer.applyBlur` and `Painter.setBlurShader` cannot consume another graph node or
  publish their result to multiple consumers.
- Next: implement a separable blur node over pixel.image.002 with declared edge and crop behavior.
- Complete when: blur composes with offset, blend, and merge, propagates its expanded bounds, and
  CPU/OpenGL parity covers transparent edges and large radii.
- Related: pixel.image.002, app.capture.004

### pixel.image.004 — No composable transform effect node

- Evidence: the current planned offset-only node would not cover the ordinary image-filter need to
  transform, crop, and tile an input with explicit sampling. Direct2D and Skia both expose general
  transform nodes.
- Next: make translation the first case of an affine transform node, with crop and tile policy in
  options rather than separate hard-wired evaluation paths.
- Complete when: an input can be translated, scaled, rotated, cropped, and tiled while bounds and
  sampling remain deterministic on both renderers.
- Related: pixel.image.002, pixel.image.046, app.capture.004

### pixel.image.005 — No composable color-matrix effect node

- Evidence: eager image filters change individual channels, but no rendered input can receive a
  4x5 RGBA matrix inside an effect graph.
- Next: add the node with explicit straight/premultiplied and working-space behavior.
- Complete when: the node represents saturation, grayscale, channel exchange, tint, and alpha
  scaling without special cases, and agrees on CPU and GPU in the chosen working space.
- Related: pixel.image.002, pixel.image.018

### pixel.image.006 — No composable blend effect node

- Evidence: painter blend modes combine a new draw with the active target; they cannot combine two
  named effect results without caller-managed render targets.
- Next: expose two graph inputs, the painter's complete artistic blend family, and a clear input
  order and alpha contract.
- Complete when: every portable painter blend mode combines two graph branches with parity and
  color-space tests.
- Related: pixel.image.002, pixel.image.018

### pixel.image.007 — No composable merge effect node

- Evidence: callers must currently build an ordered source-over merge as a chain of manual layers
  or pairwise blends.
- Next: add an ordered variadic graph node with empty and single-input semantics.
- Complete when: zero, one, and many inputs have specified bounds and ownership, and a shared input
  is evaluated once even when several merge branches reference it.
- Related: pixel.image.002

### pixel.image.045 — The effect baseline stops before masks and spatial filters

- Evidence: Direct2D's standard effect set includes alpha mask, convolution, morphology,
  displacement, transfer curves, and lighting. Pixel has eager `applyKernel`, but the planned graph
  covers only blur, transform, color matrix, blend, and merge; SVG also cannot model `in`, `in2`,
  named `result` values, `filterUnits`, or `primitiveUnits`.
- Next: after pixel.image.002 lands, rank the missing node families against SVG filters, capture
  effects, and image-editor consumers; commit only the smallest coherent v1 set and map SVG filter
  references onto the same DAG.
- Complete when: the v1 node matrix records support, fallback, bounds, and color behavior for CPU
  and GPU, and SVG no longer maintains a separate effect execution model.
- Related: pixel.image.002, pixel.image.010, pixel.image.018

---

## Tier A — SVG input fidelity

### pixel.image.008 — Radial gradients lose their focus and elliptical space

- Evidence: the parser reads `fx`, `fy`, and `fr`, but `Brush` carries only one center and scalar
  radii. Object-bounding-box gradients over non-square bounds are consequently sampled as circles.
- Next: give the brush a focus point and gradient-space transform, then implement the two-point
  conical equation in both samplers.
- Complete when: focal and focal-radius fixtures match browser rendering, a wide
  object-bounding-box radial is elliptical, and CPU/OpenGL parity covers inside, edge, and
  out-of-circle focal points.
- Related: pixel.image.010, pixel.image.018

### pixel.image.010 — SVG masks are not parsed

- Evidence: clipping supplies binary geometry coverage, but SVG masks require a rendered alpha or
  luminance image. `Layer` and `DstIn` provide most of the composition path, yet no resolve turns
  mask luminance into the alpha consumed by `DstIn`.
- Next: land `mask-type="alpha"` over layer alpha first, then add luminance-to-alpha resolve and
  parse `mask`, `maskUnits`, and `maskContentUnits`.
- Complete when: alpha and luminance masks honor their coordinate systems, black hides, white
  reveals, gradients fade continuously, unresolved references leave content unmasked, and both
  renderers agree.
- Related: pixel.image.008, pixel.image.045

---

## Tier A — Color management and display range

### pixel.image.018 — Images and rendering have no color-space contract

- Evidence: `PixelFormat` describes channels and precision but not primaries or transfer function.
  Brushes, gradients, blending, interpolation, filters, textures, render targets, and surfaces
  therefore cannot distinguish sRGB-encoded values from linear-light values.
- Next: define immutable color-space identity, default assumptions, conversion points, and the
  working space for every operation family before adding profile parsing.
- Complete when: an image and a surface each declare their color space, conversion is explicit,
  linear-light and encoded-space operations are intentionally distinguished, and CPU/GPU fixtures
  catch dark-edge and gradient errors.
- Related: pixel.image.005, pixel.image.006, pixel.image.019, pixel.image.020, pixel.image.021

### pixel.image.019 — Embedded ICC profiles are preserved but not interpreted

- Evidence: PNG `iCCP` and JPEG application records can survive as opaque metadata, but Pixel
  cannot validate a profile, derive a color space from it, or convert pixels through it.
- Next: choose the supported matrix/TRC and LUT profile classes, define invalid-profile behavior,
  and integrate conversion with the pixel.image.018 color-space object.
- Complete when: embedded sRGB, Display P3, grayscale, and one LUT-profile fixture convert to a
  declared destination with reference tolerances, while unsupported profiles are reported without
  discarding their bytes.
- Related: pixel.image.018, pixel.image.020, pixel.image.044

### pixel.image.020 — No wide-gamut surface contract

- Evidence: float and 16-bit images can store values precisely, but painter targets remain RGBA8
  and no image, texture, or display surface can declare Display P3 or Rec.2020 primaries.
- Next: make wide-gamut image/texture/render-target formats and output conversion part of the
  renderer capability contract.
- Complete when: Display P3 content retains out-of-sRGB colors through load, effects, composition,
  and presentation on a capable surface, with a defined conversion on an sRGB surface.
- Related: pixel.image.018, pixel.image.019, pixel.image.021, platform.portability.066

### pixel.image.021 — No HDR presentation and tone-mapping path

- Evidence: half/full-float CPU images retain extended values, but render targets are RGBA8 and no
  API carries transfer function, reference white, mastering/content-light metadata, display
  capability, or tone-map policy. Direct2D's advanced-color sample uses an FP16 pipeline and
  explicit display adaptation.
- Next: define scRGB/PQ/HLG representation boundaries, scene/display luminance units, FP16 surface
  capabilities, metadata ownership, and HDR-to-SDR fallback before choosing a tone mapper.
- Complete when: an HDR fixture reaches a capable display without clipping, produces a stable SDR
  rendering through an explicit tone mapper, and never silently treats encoded PQ as linear RGB.
- Related: pixel.image.018, pixel.image.019, pixel.image.020, pixel.image.026

---

## Tier B — Multi-image and bounded processing

### pixel.image.040 — Multi-frame decoding is GIF-specific

- Evidence: `Gif.Decoder` exposes sequential `nextFrame`, `frameCount`, and `rewind`, but
  `IImageDecoder` can return only one `Image`. APNG and animated WebP are explicitly rejected, GIF
  encoding writes one frame, and TIFF/ICO/EXR secondary images have no common model.
- Next: define a format-neutral decoder/image-set contract for canvas, frame rectangle, duration,
  disposal, blend, loop count, random versus sequential access, and still-image fallback; migrate
  GIF before adding another animated codec.
- Complete when: the generic API can drive GIF and at least APNG or animated WebP without
  format-specific casts, preserves timing/disposal semantics, enforces pixel.image.036 limits, and
  still-image callers receive the documented representative frame.
- Related: pixel.image.026, pixel.image.027, pixel.image.036, pixel.image.038

### pixel.image.043 — Image pipelines always materialize full intermediates

- Evidence: image operations mutate a complete owned buffer and use at most one complete working
  image. In contrast, libvips joins demand-driven region producers, keeps only active tiles in RAM,
  and streams the sink; image size and pipeline length do not multiply peak memory.
- Next: measure real large-image consumers, then design a read-only region producer and streaming
  sink for the subset of local operations that can be tiled; keep global analyses such as
  `smartcrop` explicitly separate.
- Complete when: a crop/resize/color pipeline over an image larger than RAM has bounded measured
  peak memory, deterministic edge halos, parallel tile execution, and the same output as the eager
  path within stated tolerance.
- Related: pixel.image.038, pixel.image.039

---

## Tier B — Image and texture codecs

### pixel.image.026 — No AVIF codec

- Evidence: AVIF 1.2 covers SDR, HDR/WCG, alpha, image sequences, progressive layers, auxiliary
  depth, and tone-map derived images. Treating it as an 8-bit still codec would immediately create
  debt across color and animation.
- Next: choose an AV1/HEIF dependency and first supported profile, then land still decode/encode
  with explicit bit-depth, YUV, alpha, color, metadata, and limit behavior.
- Complete when: 8/10/12-bit still fixtures with and without alpha decode and round-trip within
  codec tolerance, malformed containers obey shared limits, and unsupported sequence/HDR features
  are reported rather than silently flattened.
- Related: pixel.image.018, pixel.image.021, pixel.image.036, pixel.image.040

### pixel.image.027 — No JPEG XL codec

- Evidence: JPEG XL combines lossy and lossless coding with alpha, animation, layers, thumbnails,
  progressive decode, metadata, and lossless JPEG reconstruction. Its contract is independent of
  AVIF even when both use the same color and animation abstractions.
- Next: choose a dependency and a still-image v1 profile, including whether legacy-JPEG
  reconstruction bytes are preserved.
- Complete when: lossy and lossless still fixtures across supported precision and alpha decode and
  encode, color metadata reaches pixel.image.018, and unsupported animation/layer features fail
  explicitly.
- Related: pixel.image.018, pixel.image.036, pixel.image.040

### pixel.image.041 — DDS and KTX2 are flattened to one base-level image

- Evidence: both decoders now exist, but each returns the base level's first layer and face as one
  `Image`. The public model cannot retain mip levels, array layers, cubemap faces, volume slices,
  per-level metadata, or the container's original block payload.
- Next: define a texture-source value distinct from `Image`, with indexed levels/layers/faces,
  dimensions, format/color metadata, borrowed versus owned payloads, and explicit selection APIs;
  migrate KTX2 before extending DDS.
- Complete when: a mipmapped cubemap array can be inspected and one subresource decoded without
  flattening the rest, while ordinary `Image.load` retains its documented base-image fallback.
- Related: pixel.image.039, pixel.image.042, platform.portability.066

### pixel.image.042 — GPU-compressed texture data cannot reach the GPU compressed

- Evidence: BC1 through BC5 are decoded to RGBA8; KTX2 BasisLZ, Zstandard, ETC, ASTC, BC6H, and BC7
  are unsupported; `IRenderer.addImage` accepts only decoded `Image` or YUV420. KTX2 is designed for
  per-level streaming and Basis Universal transcoding to a GPU-native block format.
- Next: add compressed-format capability queries and texture upload from pixel.image.041, then
  choose native block families and a Basis Universal transcoder from the target matrix.
- Complete when: a KTX2 Basis or supported native-block fixture uploads without an RGBA expansion,
  chooses a supported target deterministically, preserves mip levels, and has an explicit CPU
  fallback.
- Related: pixel.image.041, pixel.image.046, platform.portability.066

### pixel.image.047 — WebP encoding is lossless-only

- Evidence: WebP decode covers VP8 and VP8L, but the encoder writes only VP8L. A caller cannot make
  the ordinary quality/size tradeoff for photographic WebP output despite the module already
  understanding the lossy bitstream on input.
- Next: define lossy encoder options for quality, alpha quality, chroma, method, and metadata, then
  implement or adopt a VP8 still encoder independently of animation.
- Complete when: opaque and alpha photographic fixtures encode at bounded quality settings,
  metadata behavior is explicit, and decoded distortion/size regressions are measured.
- Related: pixel.image.018, pixel.image.040

### pixel.image.048 — JPEG encoding cannot produce progressive output

- Evidence: JPEG decode handles baseline and progressive scans, but encoding is baseline-only.
  Progressive delivery remains a common web/export requirement and exercises a different scan and
  Huffman contract rather than a flag on the current writer.
- Next: define a scan script and coefficient lifetime for progressive Huffman encoding, reusing the
  existing DCT and metadata writer.
- Complete when: grayscale and RGB fixtures encode with multiple valid scans, decode identically to
  their baseline equivalents within JPEG tolerance, and malformed scan plans are rejected.

### pixel.image.049 — OpenEXR PIZ compression is not decoded

- Evidence: decode accepts single-part RGB/RGBA/Y scanlines with none, ZIPS, or ZIP compression;
  encode is uncompressed. OpenEXR identifies PIZ as its wavelet/Huffman lossless option, and files
  using it are rejected before the otherwise supported half/float channels can be reconstructed.
- Next: implement PIZ decode for the existing scanline RGB(A)/Y contract and validate it against
  the reference library before deciding whether PIZ encoding is justified.
- Complete when: half and float PIZ scanline fixtures decode to reference pixels, malformed wavelet
  and Huffman data fail within pixel.image.036 limits, and unsupported channel layouts still fail
  explicitly.
- Related: pixel.image.036, pixel.image.050

### pixel.image.050 — Tiled and multi-resolution OpenEXR images are rejected

- Evidence: OpenEXR tiles provide random rectangular access and can carry mipmap or ripmap levels,
  but Pixel accepts scanline images only. This blocks native region/scale decode even when the file
  already contains the needed subdivision and resolution.
- Next: expose tiled single-part RGB(A)/Y input through the region and subresource contracts from
  pixel.image.039 and pixel.image.041, including one-level, mipmap, and ripmap indexing.
- Complete when: callers can inspect levels and decode a selected tile or bounded region without
  materializing the base image, with reference fixtures for incomplete edge tiles and both level
  rounding modes.
- Related: pixel.image.039, pixel.image.041, pixel.image.043, pixel.image.049

---

## Tier B — Texture sampling fidelity

### pixel.image.046 — Painter texture sampling stops at nearest and bilinear

- Evidence: `InterpolationMode` has only `Pixel` and `Linear`; generic textures have no mip chain,
  cubic reconstruction, anisotropic policy, or explicit edge mode. Minified or oblique content
  therefore aliases, while large magnification cannot select a higher-quality reconstruction.
- Next: define sampling as a value contract separating reconstruction filter, mip selection, and
  edge behavior; implement one CPU/GPU cubic mode and mipmapped linear minification before
  considering anisotropy.
- Complete when: scale-up, scale-down, tiled edges, and oblique-transform fixtures select the same
  declared sampler on both backends, and mip use has measured aliasing and memory behavior.
- Related: pixel.image.004, pixel.image.041, pixel.image.042

---

## Tier C — Vector output

### pixel.image.022 — No painter-native PDF output

- Evidence: the PDF writer lives above Pixel in `std/gui` and cannot consume an arbitrary painter
  recording while preserving paths and text.
- Next: decide whether to move that writer below both consumers or implement a painter command
  visitor over it; do not create a second unrelated PDF serializer.
- Complete when: supported paths, text, clipping, transforms, and raster images remain native PDF
  objects, unsupported effects have a documented raster fallback, and printing no longer depends
  on GUI internals.
- Related: pixel.image.023, pixel.image.024, app.capture.001, std.gui.030

### pixel.image.023 — No arbitrary painter-to-SVG output

- Evidence: `Svg.Document` serializes its own narrow shape model, not a completed painter command
  stream containing text, clips, layers, textures, and blend modes.
- Next: define a painter recording visitor and explicit vector/raster fallback policy shared with
  PDF where the formats permit it.
- Complete when: portable painter commands serialize to SVG with preserved vector geometry and
  text, and unsupported operations rasterize only their minimal affected bounds.
- Related: pixel.image.022

### pixel.image.024 — No PostScript output

- Evidence: printing targets may still require PostScript, but neither the PDF writer nor Pixel has
  such a surface.
- Next: validate an actual consumer and target before committing an implementation; if justified,
  define it as a distinct backend over the same recording visitor.
- Complete when: either a named target proves unnecessary and the entry is removed, or that target
  receives a conforming document with explicit raster fallbacks.
- Related: pixel.image.022

---

## Tier C — Geometry and path effects

### pixel.image.032 — No path trimming effect

- Evidence: dashing exists, but a caller cannot retain only a normalized or absolute arc-length
  interval of a path for reveal animation, progress strokes, or motion graphics.
- Next: implement trimming over the public measurement contract from pixel.image.033, including
  wrapped and closed intervals.
- Complete when: line, quadratic, cubic, arc, multi-contour, closed, empty, and wrapped paths trim
  with stated tolerance and preserve contour direction.
- Related: pixel.image.033, pixel.image.034, pixel.image.035

### pixel.image.033 — No public path measurement

- Evidence: flattening computes private segment geometry, but callers cannot obtain total length or
  sample a point and tangent at distance.
- Next: expose an immutable measurement object or operation with declared flattening tolerance and
  contour selection.
- Complete when: total length and clamped point/tangent sampling cover every segment kind, empty and
  zero-length contours, and repeated sampling does not re-flatten the path.
- Related: pixel.image.032

### pixel.image.034 — No corner path effect

- Evidence: rounded rectangles are primitives, but arbitrary polyline/path corners cannot be
  replaced by tangent arcs before stroking or filling.
- Next: define radius clamping, open/closed contour behavior, and curve-corner policy, then produce
  a new path without mutating the source.
- Complete when: acute, obtuse, short-edge, open, closed, and self-intersecting fixtures have stable
  geometry and preserve winding where defined.
- Related: pixel.image.032, pixel.image.033

### pixel.image.035 — Painter paths cannot use polygon boolean operations

- Evidence: `poly/` has boolean operations, but `LinePathList` callers have no supported conversion
  with a shared tolerance, fill rule, scale, and failure contract.
- Next: define conversion in both directions and expose union, intersection, difference, and xor at
  the painter-path boundary.
- Complete when: curved, holed, touching, self-intersecting, empty, and large-coordinate fixtures
  state their approximation and fill behavior and no caller reimplements flattening.
- Related: pixel.image.032, pixel.image.033

---

## Out of scope

**A retained scene graph.** `pixel` is an immediate/deferred painter plus an imaging library;
`gui` owns the retained tree. The effect DAG in pixel.image.002 describes image production, not a
second UI hierarchy.

**Text shaping and font-format completion.** Pixel consumes positioned glyphs and owns painter text
caches, but GSUB/GPOS shaping, variable fonts, and color-glyph formats are tracked in
[font.truetype.md](font.truetype.md).

**A specific modern GPU backend chosen in isolation.** Pixel owns the renderer interface and parity
contract, but the next implementation must follow the operating-system and hardware matrix in
platform.portability.066.

**Deep EXR samples, editable PSD layers, and a general document-layer model.** These are not one
flat `Image`. Add a specialized image-set or document contract only when a named application needs
to preserve and edit them; do not silently flatten them and call the format complete.

**Video decoding.** WebP VP8 exists because WebP needs it, and YUV420 exists to hand decoded planes
to a renderer. A timed media pipeline belongs in `std/video`.
