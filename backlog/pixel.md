# Pixel Backlog

This backlog covers `std/pixel`, measured against the 2D graphics libraries it competes
with: Skia, Cairo, Blend2D, NanoVG, ThorVG, and Direct2D — plus stb_image and libvips on the
imaging side.

Evidence, investigations, and intended outcomes owned by `bin/std/modules/pixel` stay together
here. Compiler and language work belongs in [compiler.md](compiler.md) and
[language.md](language.md).
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

### T-426 — JPEG chroma sampling is limited to one block per unit

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
- Related: [video.md](video.md)

### T-049 — No image filter graph

- Problem: blur exists only as a painter shader (`setBlurShader`), applied to what is being drawn.
  There is no graph that applies a composable effect to a rendered result or chains effect output
  into another effect.
- Consequence: the standard way to build a shadow, a glow, a duotone, or a saturation adjustment
  over arbitrary content is unavailable. `image/filter/` operates on an `Image` in memory, which is
  not the same tool.
- Fix the graph evaluation, render-target lifetime, bounds propagation, caching, and composition
  contract independently of its concrete effect nodes.
- Related: T-371, T-372, T-373, T-374, T-375

### T-371 — No composable blur effect node

Apply blur to a rendered input inside T-049's graph, independently of the painter's draw-time blur
shader.

- Related: T-049, T-310

### T-372 — No composable offset effect node

Translate an effect input while correctly expanding and propagating its bounds.

- Related: T-049, T-310

### T-373 — No composable color-matrix effect node

Apply a declared color matrix inside the graph with the working-space behavior coordinated with
T-052.

- Related: T-049, T-052

### T-374 — No composable blend effect node

Blend two graph inputs using the painter's artistic blend modes and T-052's color-space contract.

- Related: T-049, T-052

### T-375 — No composable merge effect node

Merge an ordered set of graph inputs without requiring them to be blended pairwise by callers.

- Related: T-049

## Tier A — SVG input fidelity

### T-186 — SVG gradient geometry is incomplete

- Linear and centered radial paint servers, stops, spreads, percentages, user-space units and
  translate/scale gradient transforms are parsed. Radial focal points and non-square
  object-bounding-box ellipses still need a brush representation that both renderers share.
- Gradient inheritance resolves an already parsed `href`; forward inheritance chains and cycles
  still need a deferred resolver with explicit invalid-reference behavior.
- Related: T-189, T-191, T-192

### T-189 — SVG clipping paths are not parsed

Implement `clipPath` over the existing painter clipping facilities.

- Related: T-049, T-186, T-326

### T-326 — SVG masks are not parsed

Implement `mask` as a compositing operation over render targets independently of clipping paths.

- Related: T-049, T-186, T-189

### T-191 — SVG markers are not parsed

Implement start, mid, and end markers with correct path tangent orientation.

- Related: T-186, T-209

### T-192 — SVG symbols are not parsed

Implement `symbol` instancing and viewport behavior independently of ordinary `use` references.

- Related: T-186

---

## Tier B — Pixel precision and representation

### T-051 — No 16-bit integer pixel formats

- `PixelFormat` is `BGR8`, `BGRA8`, `RGB8`, `RGBA8`. Add 16-bit integer RGB/RGBA formats with codec,
  filter, conversion, and render-target behavior stated.
- Consequence: no HDR imaging, no high-precision intermediate for a filter chain, and no headroom
  in the render targets that T-049 would introduce. A multi-stage effect graph quantising to
  eight bits at every step is where banding comes from.
- Related: T-195, T-196, T-197

### T-195 — No half-float pixel formats

Add half-float formats with defined NaN, infinity, conversion, and render-target semantics.

- Related: T-051, T-052, T-200, T-207, T-353

### T-353 — No full-float pixel formats

Add full-float formats independently of half precision, preserving the same conversion and
render-target contract.

- Related: T-195, T-207

### T-196 — No single-channel pixel format

Add grayscale/mask storage suitable for distance fields and effect masks without expanding each
sample to RGB.

- Related: T-051, T-189

### T-197 — Premultiplication is not represented in pixel formats

Make straight versus premultiplied alpha explicit in the type or format contract and test every
conversion boundary.

- Related: T-051, T-052

## Tier B — Colour management and display range

### T-052 — No colour management

- Nothing in the API distinguishes sRGB from linear. Declare the working space and transfer
  behavior in images, brushes, blending, filters, and surfaces.
- The consequence is not only missing features. Compositing non-linear sRGB values directly is the
  standard cause of gradients and antialiased edges reading darker than they should — so this is a
  fidelity question, not a checkbox. Skia and Direct2D both take a position on it; this module
  takes none, which means the caller cannot take one either.
- Related: T-195, T-198, T-199, T-200

### T-198 — No ICC profile handling

Read, preserve, and convert embedded ICC profiles independently of choosing the default working
space.

- Related: T-052

### T-199 — No wide-gamut surface contract

Let images and surfaces declare a wide-gamut space such as Display P3 and convert to it correctly.

- Related: T-052, T-198, T-200

### T-200 — No HDR output path

Define HDR surface formats, transfer functions, luminance metadata, and tone-mapping boundaries.

- Related: T-195, T-199

---

## Tier C — Rendering backends and vector output

### T-053 — OpenGL is the only GPU backend

- `render/` has `cpu` and `ogl`. There is no Vulkan, Direct3D, Metal or WebGPU path.
- On Windows this is the weakest choice available: OpenGL driver quality varies widely, and some
  ARM devices have no usable implementation at all. Skia ships GL, Vulkan, Metal and D3D.
- This also intersects
  [T-028](core.md#t-028--process-services-have-no-second-platform-backend). A second platform
  needs a second backend regardless,
  so choose the target with that in mind rather than twice.
- The backend boundary is already two implementations deep, so a third is additive.

### T-054 — No vector output

Add PDF output that preserves text and paths as vectors and embeds raster content at source
resolution. This is the vector target needed by printing.

- Note: the repository's PDF writer lives in `std/gui` (`gui/src/controls/pdf/encode.swg`), above
  this module. Taking this entry up means either moving that writer below both consumers or
  growing a painter-native one here; do not duplicate it silently.
- Related: T-201, T-202, T-238, T-047

### T-201 — No SVG output

Serialize supported painter content to SVG with explicit fallback behavior for effects and raster
operations that have no direct representation.

- Related: T-054, T-186

### T-202 — No PostScript output

Add PostScript only as a separately justified output backend; it must not be hidden inside PDF
completion.

- Related: T-054

## Tier C — Image and texture codecs

### T-055 — No QOI codec

Add QOI encoding and decoding as the smallest remaining general-purpose codec.

- Related: T-203, T-204, T-205, T-206, T-207, T-208

### T-203 — No AVIF codec

Add AVIF decoding and encoding as its own dependency and color-management decision.

- Related: T-052, T-055

### T-204 — No JPEG XL codec

Add JPEG XL decoding and encoding independently of AVIF.

- Related: T-055

### T-205 — No DDS texture container

Read and write DDS metadata and supported block-compressed payloads without coupling it to KTX2.

- Related: T-053, T-206

### T-206 — No KTX2 texture container

Read and write KTX2 and define which GPU-compressed formats can remain compressed through upload.

- Related: T-053, T-205

### T-207 — No EXR codec

Add OpenEXR-compatible high-dynamic-range image I/O after floating-point formats exist.

- Related: T-195

### T-208 — No PSD importer

Import a documented PSD subset, including how layers, masks, color modes, and unsupported effects
map into Pixel structures.

- Related: T-049, T-055

## Tier C — Geometry and font resources

### T-056 — Path effects

Dashing exists. Add path trimming by normalized or absolute arc-length ranges.

- Related: T-209, T-210, T-211

### T-209 — No public path arc-length measurement

Expose total length and point/tangent sampling with stated flattening tolerance.

- Related: T-056, T-191

### T-210 — No corner path effect

Add a corner-rounding effect independently of trimming and measurement.

- Related: T-056

### T-211 — Painter paths cannot use polygon boolean operations

Define the conversion and tolerance contract that makes `poly/` boolean operations available to a
painter path.

- Related: T-056

### T-057 — A collection face is selected by name, and a localized Windows will miss

`TypeFace.createFromHfont` now asks GDI for the `ttcf` table, and picks the face out of the
collection by matching the family GDI enumerated against `Face.familyNameAt`. That match is between
the name Windows reports for the current locale and the best-scoring `name` record in the face,
which this module scores towards English. Where they disagree the match fails and face zero is
taken, which is a wrong family rather than a refusal.

Verified on a French Windows 11: all twelve collection-backed families — `MS Gothic`, `MS PGothic`,
`MS UI Gothic`, `Cambria`, `Cambria Math`, `SimSun`, `NSimSun`, `Yu Gothic`, `Nirmala UI`,
`Nirmala Text`, `Microsoft JhengHei`, `Microsoft YaHei` — resolve to their own face and render.
A Japanese or Chinese Windows enumerates `ＭＳ ゴシック` and `宋体` instead, and has not been tried.

The bounded fix is to match against every `name` record a face declares rather than only the
best-scoring one, which needs `truetype` to answer "does this face call itself X" rather than
"what is this face called". Weigh that against reading the face index out of the offset tables
instead, which is locale-proof but needs the synthesized single-face file as well as the
collection, and so reads the font twice.

---

## Out of scope

**A scene graph or a retained-mode API.** `pixel` is an immediate-mode painter plus an imaging
library, and `gui` owns the retained tree above it. Do not grow a second one here.

**Video decoding.** The WebP VP8 decoder exists because WebP needs it, not as the beginning of a
media stack. If `sSnapForge` ever records video, that belongs in its own module.

---

The entries below were open investigations when the unified backlog was introduced. Their `F-*`
identifiers remain permanent; update their next action in place as the evidence matures. They retain
their former order until re-triaged, so position in this imported block carries no priority claim.

These leads cover images, text, and the CPU/OpenGL painters.

### F-075 — A cached typeface keeps a second copy of the whole font file

- Area: std/pixel
- Found while: reordering `TypeFace.createFromHfont` so its failure path stops dropping an
  unassigned face
- Observation: `TypeFace.buffer` holds the bytes GDI returned, described as "kept alive for the
  native face". `Face.load` does not borrow them: it copies the whole file into its own
  `FaceImpl.fontData` and every slice it hands out points there. So each cached typeface holds the
  font twice.
- Evidence: `Face.loadAt` in `bin/std/modules/truetype/src/face.swg` resizes `faceData.fontData` to
  `@countof(bytes)` and copies into it before parsing anything. For a collection the cost is the
  whole collection: `msgothic.ttc` is 8.99 MB, so `MS Gothic`, `MS PGothic` and `MS UI Gothic`
  cached together hold about 54 MB where 27 MB is reachable.
- Next step: decide which of the two owns the bytes. Either drop `TypeFace.buffer` and let the face
  own its copy, which is one line and costs nothing; or give `truetype` a borrowing entry point
  that keeps the caller's slice and does not copy, which removes the duplicate on every path and
  not just this one — but it makes the face's lifetime depend on the caller's buffer, which is a
  contract change worth stating deliberately.

### F-121 — Text shading and bilinear texture lerps still dominate a CPU-rendered widget frame

- Area: std/pixel (RenderCpu)
- Found while: cutting headless-test frame times with the batch rasterizer fast paths
- Observation: after the constant-fill, copy-blit, DstIn-skip, and BGRA8 fetch fast paths, a
  900x700 fast-debug frame fell from 141 ms to 29 ms when empty, but a frame carrying 80 themed
  buttons stays near 200 ms. Adding 40 text labels changes almost nothing, and the residual
  concentrates in the paths that cannot keep bytes stable without care: `shadeMsdf` evaluates
  four supersample coverages of four bilinear atlas fetches plus a `pow` per shaded pixel, and
  a bilinear texture paint runs three `lerpColor` round trips through `fromArgbF32` per pixel.
- Evidence: isolated probe module driving `Gui.Testing.HeadlessHost` (2026-08-12, fast-debug,
  serial painter scenes): full-surface opaque fill 366 -> 19.6 ms, alpha fill 394 -> 31 ms,
  empty host frame 141 -> 29 ms, 80-button frame 480 -> ~200 ms, and buttons+labels ~= buttons.
  The gui suite run dropped 26.9 s -> 10.8 s for 379 tests on the same change.
- Next step: three leads, in decreasing value. Lower the presentation blit (Copy, Pixel
  interpolation, content scale 1, same-size integer rectangles) to row copies once the
  nearest-neighbour mapping is proved an identity over that domain. Share atlas fetches between
  the four MSDF coverage taps, validating against the pixel image goldens and refreshing them
  deliberately if bytes move. Replace the bilinear `lerpColor` chain with integer arithmetic
  under the same golden policy.

### F-148 — A wide, thin polygon corrupts what the painter draws after it

- Area: std/pixel
- Found while: giving the HTML engine mitred borders, so that the four sides of a box meet on the
  diagonal instead of overlapping as rectangles
- Observation: filling a border side with `Painter.fillPolygon` instead of `Painter.fillRect`
  produced a rendering in which unrelated, later boxes were drawn at the wrong position and with
  the wrong size — a 1400x2 strip in the page accent came out as a 1400x68 band, and a code block
  eight hundred pixels down the document was drawn at the top of the viewport. The geometry handed
  to the painter was verified correct at the call: the box rectangle, the four corners and the
  colour all printed the values the layout computed. Only the drawn result disagreed. Restricting
  the polygon path to boxes smaller than the viewport made every artefact disappear, and the same
  sides drawn as rectangles are correct at any size.
- Evidence: `paintDecorations` in
  [paint.swg](../bin/std/modules/gui/src/controls/html/paint.swg) now takes the polygon
  path only for a box smaller than the visible band whose sides differ in colour, and the
  rectangle path otherwise; the comment there records why. Reproduce by removing that condition
  and rendering `web/std.pixel.html` at 1400x1000 through `Testing.HeadlessHost`.
- Next step: reproduce it in `pixel` alone, without the HTML engine: fill a 1400x2 quadrilateral
  with `fillPolygon`, then fill an ordinary rectangle, and compare against the same pair drawn
  with `fillRect`. `fillPolygon` routes a shape its convexity test rejects through
  `Polygon.cleanedPaths`, which is the first thing to look at for a strip whose four corners are
  nearly collinear.
