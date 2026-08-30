# Pixel Backlog

This backlog covers `std/pixel`, measured against the 2D graphics libraries it competes
with: Skia, Cairo, Blend2D, NanoVG, ThorVG, and Direct2D — plus stb_image and libvips on the
imaging side.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/pixel` stay together
here. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md).
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

This is the strongest module in the tree, and several parts of it are ahead of the field.

- **Codecs**: eight decoders and eight encoders — BMP, GIF, ICO, JPEG including progressive, PNG,
  TGA, TIFF, WebP with both the lossless and VP8 paths. Round-tripping eight formats is more than
  stb offers and more than most graphics libraries carry at all.
- **Computational geometry**: `poly/` has boolean path operations, path offsetting, and Delaunay
  triangulation. Skia exposes far less of this and Cairo none.
- **Math typesetting**: `math/expression.swg` and `math/layout.swg` implement TeX-style
  formula layout with display, text, script and script-script styles. No competing 2D library has
  this. It is a real differentiator and nothing on this list should put it at risk.
- **Distance-field text** through the `truetype` MSDF path, which is what GPU text actually wants.
- **Imaging**: thirteen filters and eleven transforms, including content-aware `smartcrop` and Haar
  feature statistics.
- **Painter**: a full state stack, transform stack, clipping rectangles *and* clipping regions with
  set operations, render targets, custom shaders, layers, and integrated DPI content scale.
- Two backends behind one API — CPU and OpenGL — with command-stream golden regression tests.

The gaps are in composition fidelity, color, and the GPU backend.

---

## Tier A — Composable image effects

### B-467 — JPEG chroma sampling is limited to one block per unit

- Problem: `Jpg.Decoder` recognizes four layouts by their sampling numbers, and every one of them
  needs the two chroma components to sample `1x1`. That covers every still image in practice, and
  not the Motion JPEG ffmpeg writes: its 4:2:2 and 4:4:4 frames sample chroma `1x2`, so they are
  refused with `JPEG chroma sampling of 1x2 is not supported`.
- Consequence: `std/video` opens such an AVI, reports its geometry, its rate and its frame table,
  and then cannot show a single picture — and ffmpeg is the most common producer of these files.
  `bin/std/modules/video/src/tests/datas/ffmpeg-mjpeg-422.avi` and its 4:4:4 sibling
  reproduce it, and the tests in `avi.test.swg` assert the refusal today.
- Note that the sampling factors cannot simply be reduced by their common divisor: they decide how
  blocks are grouped into a minimum coded unit, so changing them changes the order of the entropy
  coded stream and decodes the frame to noise.
- Fix by walking a minimum coded unit and upsampling chroma from the sampling factors themselves,
  instead of dispatching to four hand-written converters. Complete when both fixtures decode to
  the same pictures as their 4:2:0 sibling.
- Related: [std.video.md](std.video.md)

### B-205 — No image filter graph

- Problem: blur exists only as a painter shader (`setBlurShader`), applied to what is being drawn.
  There is no graph that applies a composable effect to a rendered result or chains effect output
  into another effect.
- Consequence: the standard way to build a shadow, a glow, a duotone, or a saturation adjustment
  over arbitrary content is unavailable. `image/filter/` operates on an `Image` in memory, which is
  not the same tool.
- Fix the graph evaluation, render-target lifetime, bounds propagation, caching, and composition
  contract independently of its concrete effect nodes.
- Related: B-433, B-434, B-435, B-436, B-437

### B-433 — No composable blur effect node

Apply blur to a rendered input inside B-205's graph, independently of the painter's draw-time blur
shader.

- Related: B-205, B-388

### B-434 — No composable offset effect node

Translate an effect input while correctly expanding and propagating its bounds.

- Related: B-205, B-388

### B-435 — No composable color-matrix effect node

Apply a declared color matrix inside the graph with the working-space behavior coordinated with
B-207.

- Related: B-205, B-207

### B-436 — No composable blend effect node

Blend two graph inputs using the painter's artistic blend modes and B-207's color-space contract.

- Related: B-205, B-207

### B-437 — No composable merge effect node

Merge an ordered set of graph inputs without requiring them to be blended pairwise by callers.

- Related: B-205

## Tier A — SVG input fidelity

### B-307 — SVG gradient geometry is incomplete

- Linear and centered radial paint servers, stops, spreads, percentages, user-space units and
  translate/scale gradient transforms are parsed. Radial focal points and non-square
  object-bounding-box ellipses still need a brush representation that both renderers share.
- Gradient inheritance resolves an already parsed `href`; forward inheritance chains and cycles
  still need a deferred resolver with explicit invalid-reference behavior.
- Related: B-308, B-309, B-310

### B-308 — SVG clipping paths are not parsed

Implement `clipPath` over the existing painter clipping facilities.

- Related: B-205, B-307, B-402

### B-402 — SVG masks are not parsed

Implement `mask` as a compositing operation over render targets independently of clipping paths.

- Related: B-205, B-307, B-308

### B-309 — SVG markers are not parsed

Implement start, mid, and end markers with correct path tangent orientation.

- Related: B-307, B-325

### B-310 — SVG symbols are not parsed

Implement `symbol` instancing and viewport behavior independently of ordinary `use` references.

- Related: B-307

---

## Tier B — Pixel precision and representation

### B-206 — No 16-bit integer pixel formats

- `PixelFormat` is `BGR8`, `BGRA8`, `RGB8`, `RGBA8`. Add 16-bit integer RGB/RGBA formats with codec,
  filter, conversion, and render-target behavior stated.
- Consequence: no HDR imaging, no high-precision intermediate for a filter chain, and no headroom
  in the render targets that B-205 would introduce. A multi-stage effect graph quantising to
  eight bits at every step is where banding comes from.
- Related: B-311, B-312, B-313

### B-311 — No half-float pixel formats

Add half-float formats with defined NaN, infinity, conversion, and render-target semantics.

- Related: B-206, B-207, B-316, B-323, B-422

### B-422 — No full-float pixel formats

Add full-float formats independently of half precision, preserving the same conversion and
render-target contract.

- Related: B-311, B-323

### B-312 — No single-channel pixel format

Add grayscale/mask storage suitable for distance fields and effect masks without expanding each
sample to RGB.

- Related: B-206, B-308

### B-313 — Premultiplication is not represented in pixel formats

Make straight versus premultiplied alpha explicit in the type or format contract and test every
conversion boundary.

- Related: B-206, B-207

## Tier B — Colour management and display range

### B-207 — No colour management

- Nothing in the API distinguishes sRGB from linear. Declare the working space and transfer
  behavior in images, brushes, blending, filters, and surfaces.
- The consequence is not only missing features. Compositing non-linear sRGB values directly is the
  standard cause of gradients and antialiased edges reading darker than they should — so this is a
  fidelity question, not a checkbox. Skia and Direct2D both take a position on it; this module
  takes none, which means the caller cannot take one either.
- Related: B-311, B-314, B-315, B-316

### B-314 — No ICC profile handling

Read, preserve, and convert embedded ICC profiles independently of choosing the default working
space.

- Related: B-207

### B-315 — No wide-gamut surface contract

Let images and surfaces declare a wide-gamut space such as Display P3 and convert to it correctly.

- Related: B-207, B-314, B-316

### B-316 — No HDR output path

Define HDR surface formats, transfer functions, luminance metadata, and tone-mapping boundaries.

- Related: B-311, B-315

---

## Tier C — Rendering backends and vector output


### B-209 — No vector output

Add PDF output that preserves text and paths as vectors and embeds raster content at source
resolution. This is the vector target needed by printing.

- Note: the repository's PDF writer lives in `std/gui` (`gui/src/controls/pdf/encode.swg`), above
  this module. Taking this entry up means either moving that writer below both consumers or
  growing a painter-native one here; do not duplicate it silently.
- Related: B-317, B-318, B-346, B-204

### B-317 — No SVG output

Serialize supported painter content to SVG with explicit fallback behavior for effects and raster
operations that have no direct representation.

- Related: B-209, B-307

### B-318 — No PostScript output

Add PostScript only as a separately justified output backend; it must not be hidden inside PDF
completion.

- Related: B-209

## Tier C — Image and texture codecs

### B-210 — No QOI codec

Add QOI encoding and decoding as the smallest remaining general-purpose codec.

- Related: B-319, B-320, B-321, B-322, B-323, B-324

### B-319 — No AVIF codec

Add AVIF decoding and encoding as its own dependency and color-management decision.

- Related: B-207, B-210

### B-320 — No JPEG XL codec

Add JPEG XL decoding and encoding independently of AVIF.

- Related: B-210

### B-321 — No DDS texture container

Read and write DDS metadata and supported block-compressed payloads without coupling it to KTX2.

- Related: B-208, B-322

### B-322 — No KTX2 texture container

Read and write KTX2 and define which GPU-compressed formats can remain compressed through upload.

- Related: B-208, B-321

### B-323 — No EXR codec

Add OpenEXR-compatible high-dynamic-range image I/O after floating-point formats exist.

- Related: B-311

### B-324 — No PSD importer

Import a documented PSD subset, including how layers, masks, color modes, and unsupported effects
map into Pixel structures.

- Related: B-205, B-210

## Tier C — Geometry and font resources

### B-211 — Path effects

Dashing exists. Add path trimming by normalized or absolute arc-length ranges.

- Related: B-325, B-326, B-327

### B-325 — No public path arc-length measurement

Expose total length and point/tangent sampling with stated flattening tolerance.

- Related: B-211, B-309

### B-326 — No corner path effect

Add a corner-rounding effect independently of trimming and measurement.

- Related: B-211

### B-327 — Painter paths cannot use polygon boolean operations

Define the conversion and tolerance contract that makes `poly/` boolean operations available to a
painter path.

- Related: B-211


---

## Out of scope

**A scene graph or a retained-mode API.** `pixel` is an immediate-mode painter plus an imaging
library, and `gui` owns the retained tree above it. Do not grow a second one here.

**Video decoding.** The WebP VP8 decoder exists because WebP needs it, not as the beginning of a
media stack. If `Swag Capture` ever records video, that belongs in its own module.
