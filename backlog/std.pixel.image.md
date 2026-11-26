# Pixel Image Backlog

This backlog covers image decoding, encoding, metadata, multi-image containers, and SVG input
owned by `bin/std/modules/pixel`. Module-wide rendering, effects, image transformations, surface,
texture-sampling, vector-output, and geometry work lives in [std.pixel.md](std.pixel.md).
Compiler issues belong in [compiler.frontend.md](compiler.frontend.md), [compiler.build.md](compiler.build.md),
[compiler.codegen.md](compiler.codegen.md), or [compiler.optimization.md](compiler.optimization.md). Language changes belong in
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
  bytes per pixel buffer. `image.imagereader.swg` protects these limits, including cyclic TIFF
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
- Evidence: an external manuscript gallery embeds JPEG photographs in roughly 1 MiB SVGs.
  Preparing two such drawings takes roughly 1–2 seconds each in devmode even for a 280-pixel
  thumbnail; `Svg.Parser.loadImage` always decodes the photograph at its full resolution.
- Next: profile the embedded JPEG decode separately from SVG parsing, then define requested
  output size, source rectangle, and orientation behavior as decoder
  capabilities with a documented fallback path.
- Done when: a caller can request a bounded thumbnail or region, determine whether the codec
  honored it natively, and receive the same pixels as the defined full-decode fallback within the
  stated resampling tolerance.
- Related: std.pixel.image.038, std.pixel.019

### std.pixel.image.057 — SVG CPU rasterization is far slower than resvg

- Evidence: a Release benchmark measured `Svg.Drawing.parse` and `Svg.Drawing.rasterize(..., 1)`
  separately on the four Filesamples SVGs. It used the same output dimensions as Scope's pixel
  image path, capped at 2048 px on the longest side, and compared against [resvg 0.50.0](https://github.com/linebender/resvg/releases/tag/v0.50.0)
  with `--perf`. Both engines ran on the CPU; seven repetitions were summarized by their medians.
  File reading, PNG saving, GUI startup, and presentation were excluded. The totals below are
  medians of each run's parse-plus-raster time, so they need not equal the sum of the two phase
  medians.

  | SVG source | Output px | SwagScope parse / raster / total ms | resvg parse / render / total ms | Total ratio |
  | --- | ---: | ---: | ---: | ---: |
  | `sample_640×426.svg` (119,951 B) | 640 × 426 | 10.106 / 128.033 / 138.530 | 1.970 / 5.530 / 7.540 | 18.4× |
  | `sample_1280×853.svg` (453,031 B) | 1280 × 853 | 35.700 / 2104.275 / 2146.360 | 7.580 / 21.340 / 28.620 | 75.0× |
  | `sample_1920×1280.svg` (1,067,956 B) | 1920 × 1280 | 21.591 / 502.368 / 526.270 | 19.180 / 47.450 / 66.890 | 7.9× |
  | `sample_5184×3456.svg` (7,905,340 B) | 2048 × 1365 | 182.785 / 4431.484 / 4619.600 | 150.440 / 254.660 / 406.530 | 11.4× |

  The largest phase gaps are rasterization: 23×, 99×, 11×, and 17× respectively. Source byte
  size alone does not predict the cost; the 453 KiB sample takes about 2.1 s to rasterize, while
  the 1.07 MiB sample takes about 0.50 s. The four inputs contain no `<text>`, `<image>`, or
  `<filter>` elements, so these timings isolate geometric SVG work and do not cover those paths.
  This is a direct Pixel API benchmark of the parse and CPU raster operations used by Scope when
  pixels are needed, not a measurement of GUI open time; Scope's normal vector view is not
  rasterized to a full-size bitmap. The source files are in the sibling
  `filesamples/samples/image/svg` corpus. SHA-256 fingerprints, in table order:
  `6c080cb0dcdb660db9e2865e0d3349f3263183e58c9345cc6122a4130ea3c8a5`,
  `00d622cf6ab0ef73e48d203d90adeab659776b6d3b1958dc71042a836694fa6a`,
  `d6012d46eab66404f9c2c450942dc8874ba6fe057774a38ba19b9fa570062a2d`,
  `bf29681a8b952f06b8d5a61a4ac5a18e0194e9f6a207e57ab6ab9b32f4e64801`.
  Benchmark host: Windows 11 x64, Intel Core Ultra 9 185H. The comparison measures this corpus
  and these output sizes only; it does not establish whole-format correctness or universal speed.
- Evidence: the [Linux Release benchmark](../bench/workloads/svgraster/README.md#original-filesamples-svgs)
  uses the same four originals. Its one-worker medians are 14.36×, 6.39×, 3.95× and 5.93×
  resvg. The largest remaining absolute gap is the 7.9 MiB sample. Its raster profile spans
  triangle drawing, contour intersection tests, transforms and scan edge construction.
- Evidence: the [resvg code comparison](../bench/workloads/svgraster/resvg-comparison.md)
  attributes most of the remaining gap to the ordinary fill path. Routing eligible black fills
  through the existing scan converter closes 68–98% of the time gap on these inputs and
  changes alpha coverage. The two largest paths in the 7.9 MiB file already scan-convert.
- Evidence: [direct CPU composition](../bench/workloads/svgraster/resvg-comparison.md#direct-cpu-composition)
  brings the largest original down to 359 ms against 269 ms for resvg on the Linux host. The
  other originals take 1.00× to 1.39× as long as resvg. Scope also uses the path for eligible
  thumbnails at its existing sample count.
- Evidence: an [active-edge prototype](../bench/workloads/svgraster/resvg-comparison.md#contour-culling-and-crossing-sort)
  improved the generated dense fill and slowed the largest original. Contour culling and
  short-line sorting improved the original corpus with matching raster checksums.
- Evidence: [phase measurements](../bench/workloads/svgraster/resvg-comparison.md#curve-projection-and-parallel-scan-rows)
  put most of the largest original's first raster in flattening and crossing collection.
  Parallel row resolution complements the reduction in work per contour. At four workers,
  Swag is faster on three originals and takes 263 ms against resvg's 255 ms on the largest.
- Evidence: [parallel contour preparation](../bench/workloads/svgraster/resvg-comparison.md#parallel-contour-preparation-and-shared-sample-rows)
  cuts the largest four-worker thumbnail by 18% with identical pixels. Swag leads resvg
  on all four original bitmaps with four workers on Linux. At one worker, the mid-size
  and largest files still spend more time rasterizing than resvg.
- Next: profile single-worker crossing collection on the mid-size and largest inputs.
  Rerun the original Windows comparison at one worker and at the runtime default.
- Done when: the original corpus meets agreed parse and raster budgets against resvg and the
  renderer's verified output behavior is preserved.
- Related: std.pixel.image.039, app.scope.image.010

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

### std.pixel.image.051 — Animated GIF palette quality and sharing need visual validation

- Evidence: `Gif.AnimationWriter` now uses up to 256 exact colours or a weighted median-cut
  palette built from the frame's colours. Ordered dithering is optional and off by default.
  The first frame supplies a global colour table, reused by later frames whose colours are all
  present in it; other frames write local tables. Quality and output size have not been measured on a
  representative screen-recording corpus.
- Next: compare anti-aliased text and gradients against the former fixed palette on the same
  captures and measure file size on representative animations.
- Done when: a screen recording with anti-aliased text exports without visible banding at a size
  comparable to the former encoder, and still frames keep their exact palette.
- Related: std.pixel.image.052

### std.pixel.image.052 — No animated PNG encoding

- Evidence: the PNG encoder writes one image; an animated capture exported losslessly, or with
  more than 256 colors, has no output.
- Next: add APNG output (`acTL`, `fcTL`, `fdAT`) on the existing PNG filter and Deflate path,
  reusing the changed-rectangle reduction of std.pixel.image.051.
- Done when: an animation written as APNG decodes back with identical pixels and timing, and
  viewers without APNG support show its first frame.
- Related: std.pixel.image.051

---

### std.pixel.image.053 — Remaining PNG sample conversion needs a current profile

- Evidence: packed bit expansion, encoder filter/scoring kernels, decoder Up/Average/Paeth
  and Sub for 1/2/3/4/6/8-byte pixels exist (`defilterSubRow` in `decode/png/filter.swg`);
  `image.png.swg` compares Sub against scalar recurrence across strides 1 through 8.
  Gray and palette conversion have thresholded packed-word paths. Native 16-bit samples
  without transparency keys are byte-swapped eight at a time, and grayscale keys
  are compared eight at a time; RGB keys are compared two pixels at a time. Earlier rejections of other packed
  Sub and gray shuffles predate cross-module SIMD inlining and do not settle the current cost.
- Next: profile current decoding by filter and bit depth, then compare the packed 16-bit
  sample and transparency-key paths against their scalar forms in the same process. Keep Inflate's
  share separate from image conversion so a microkernel gain has an end-to-end
  interpretation.
- Done when: remaining paths have a measured decision, odd/Adam7 tails and malformed rows
  retain bounds protection, and every retained kernel improves representative decoding.
- Related: std.core.043, std.core.044, compiler.codegen.022.

### std.pixel.image.054 — The JPEG forward transform and quantization remain scalar

- Evidence: the JPEG decoder and the encoder's colour conversion (`loadFromRGB` in
  `encode/jpg/dct.swg`) are packed. The encoder's float AAN forward transform and the
  quantization that follows it are scalar and now dominate encoding. Their samples go
  through an `s16` staging array because no packed `s32` to `f32` lane conversion exists
  (std.core.042).
- Next: decide whether byte-exactness with today's encoded output must be kept. Lane-by-lane
  float order can still change the last bit under multiply-add contraction, and an integer
  transform changes the bytes outright. Then profile the encoder stages before writing the
  kernel.
- Done when: fixtures preserve accepted pixel tolerances, coefficient extremes are covered,
  and encode throughput improves in an interleaved A/B on a quiet machine.
- Related: std.core.042, compiler.codegen.022.

### std.pixel.image.055 — Remaining WebP decode stages need performance decisions

- Evidence: the lossy FileSamples path uses batched entropy input, packed normal deblocking
  and YUV conversion, and dedicated DC-only reconstruction. Lossless decoding uses batched
  Huffman input, packed copies and subtract-green, and reconstructs predictor pixels as packed
  RGBA words. Dispatching the predictor per tile and vectorizing spans further reduced VP8L
  decode time. The three original VP8L fixtures take 1.6–1.9× libwebp's time in that comparison.
  Packed VP8 predictor writes reduced thread CPU time on the opaque FileSamples image from
  220 to 201 ms, against 101 ms for libwebp in the same series.
  See [the FileSamples report](../bench/results/swagscope-filesamples/README.md#opaque-webp-repeat).
- Next: profile remaining VP8 entropy and reconstruction work and the VP8L color cache on the
  photo and interface fixtures from the [raster decode workload](../bench/workloads/rasterdecode/README.md).
  Rerun the original Windows comparison.
- Done when: remaining hot stages have measured decisions and lossy and lossless output is
  preserved at the tested predictor, filter, and image boundaries.
- Related: std.core.043, compiler.codegen.022.

### std.pixel.image.056 — Remaining palette lookups need a profitable packed strategy

- Evidence: BMP/TGA 16-bit expansion, TGA row reversal and RLE spans, RGB/BGR channel shuffles,
  GIF palette expansion and fixed quantization, and PNG packed-word palette tables already have
  bulk implementations.
  Palette lookup still has no general gather/shuffle strategy that beats those direct tables.
- Evidence: a 16-entry SSSE3 PNG table shuffle lost (2.97x RGB, 1.83x RGBA) while SIMD
  wrappers were still cross-module calls; PNG's packed-u32 lookup beat the gather
  prototype. Neither result settles every palette size or target.
- Next: profile the remaining indexed layouts before selecting gather or shuffle, preserve the
  existing small-image setup thresholds, and compare against current packed-word tables.
- Done when: each remaining indexed path has a measured dispatch decision and covers palette
  size, transparency and tails without invalid reads or changes to decoded pixels.
- Related: std.core.044.

### std.pixel.image.058 — EXR and GIF need a Windows FileSamples rerun

- Evidence: the original Windows Release decode lagged ImageMagick on both fixtures, while
  the revised paths beat the local reference in the Linux follow-up. The API boundaries and
  reference versions are recorded in [the FileSamples report](../bench/results/swagscope-filesamples/README.md).
- Next: rerun the interleaved comparison on Windows with the original EXR and GIF files and
  verify the decoded pixel checksums against the baseline.
- Done when: both revised decoders preserve the baseline pixels and meet the original Windows
  reference timings on these fixtures.
