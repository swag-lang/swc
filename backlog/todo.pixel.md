# Pixel Roadmap

This file is the roadmap for `std/pixel`, measured against the 2D graphics libraries it competes
with: Skia, Cairo, Blend2D, NanoVG, ThorVG, and Direct2D — plus stb_image and libvips on the
imaging side.

It is not the repository's discovery backlog. Defects and leads belong in the `findings.*` files,
which hold evidence; compiler and language intent belongs in [todo.compiler.md](todo.compiler.md)
and [todo.language.md](todo.language.md). This file holds intent about `bin/std/modules/pixel`.
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
- **Math typesetting**: `math/mathexpression.swg` and `math/mathlayout.swg` implement TeX-style
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

## Tier A — Composition fidelity

### T-048 — No separable blend modes

- Problem: `BlendingMode` lacks the separable modes defined by PDF, SVG, CSS, Skia, and design
  tools: Multiply, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight, SoftLight,
  Difference, and Exclusion.
- Consequence: Multiply and Screen alone account for most real compositing work. Without them,
  shadow, tint, highlight and any layered design effect cannot be expressed. It is also what
  blocks [T-076](todo.scapture.md#t-076--no-capture-level-effect-pipeline), which asks for
  capture-level effects.
- Fix the separable set in both backends as one compatible family.
- This is the highest value-to-effort entry in the module.
- Related: T-185

### T-185 — No non-separable blend modes

Add Hue, Saturation, Color, and Luminosity with one stated color-space contract after the separable
modes land.

- Related: T-048, T-052

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

Blend two graph inputs using T-048's modes and T-052's color-space contract.

- Related: T-048, T-049, T-052

### T-375 — No composable merge effect node

Merge an ordered set of graph inputs without requiring them to be blended pairwise by callers.

- Related: T-049

### T-050 — Gradients cap at eight stops

- `MaxGradientStops = 8` in `src/types/brush.swg`. Design tools and SVG routinely produce more, and
  a gradient silently loses its later stops.
- Remove the silent limit or return an explicit failure when the selected backend cannot represent
  the input.
- Related: T-186

### T-186 — SVG gradients are not parsed

- `src/svg/svgparse.swg` parses `svg`, `g`, `defs`, `use`, `path`, `rect`, `circle`, `ellipse`,
  `line`, `polygon`, `polyline` and `style`. It does not parse `linearGradient`, `radialGradient`
  or `stop` — so **an SVG with a gradient renders flat**, even though `Brush` supports linear,
  radial and sweep gradients natively. The capability exists on both sides and nothing connects
  them.
- This constrains the repository directly: the GUI theme is vector — `gui/src/theme/widgets.svg`
  and `icons.svg` — so the parser's coverage is the theme's design vocabulary.
- Related: T-050, T-187, T-188, T-189, T-190, T-191, T-192, T-193, T-194

### T-187 — SVG text elements are not parsed

Implement `text` and `tspan` layout with an explicit supported subset of SVG text semantics.

- Related: T-069, T-186

### T-188 — SVG image elements are not parsed

Load bounded embedded or referenced raster images through Pixel's codec registry, with a clear
external-resource policy.

- Related: T-186

### T-189 — SVG clipping paths are not parsed

Implement `clipPath` over the existing painter clipping facilities.

- Related: T-049, T-186, T-326

### T-326 — SVG masks are not parsed

Implement `mask` as a compositing operation over render targets independently of clipping paths.

- Related: T-049, T-186, T-189

### T-190 — SVG patterns are not parsed

Implement `pattern` paint servers independently of gradients and masks.

- Related: T-186

### T-191 — SVG markers are not parsed

Implement start, mid, and end markers with correct path tangent orientation.

- Related: T-186, T-209

### T-192 — SVG symbols are not parsed

Implement `symbol` instancing and viewport behavior independently of ordinary `use` references.

- Related: T-186

### T-193 — SVG filters are not parsed

Map a declared subset of SVG filter primitives onto the effect graph from T-049.

- Related: T-049, T-186

### T-194 — SVG stroke dashes are not parsed

Parse `stroke-dasharray` and `stroke-dashoffset` into the painter's existing dash support.

- Related: T-186

---

## Tier B — Colour and precision

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

### T-052 — No colour management

- Nothing in the API distinguishes sRGB from linear. Declare the working space and transfer
  behavior in images, brushes, blending, filters, and surfaces.
- The consequence is not only missing features. Compositing non-linear sRGB values directly is the
  standard cause of gradients and antialiased edges reading darker than they should — so this is a
  fidelity question, not a checkbox. Skia and Direct2D both take a position on it; this module
  takes none, which means the caller cannot take one either.
- Related: T-185, T-195, T-198, T-199, T-200

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

## Tier C — Reach

### T-053 — OpenGL is the only GPU backend

- `render/` has `cpu` and `ogl`. There is no Vulkan, Direct3D, Metal or WebGPU path.
- On Windows this is the weakest choice available: OpenGL driver quality varies widely, and some
  ARM devices have no usable implementation at all. Skia ships GL, Vulkan, Metal and D3D.
- This also intersects
  [T-028](todo.core.md#t-028--process-services-have-no-second-platform-backend). A second platform
  needs a second backend regardless,
  so choose the target with that in mind rather than twice.
- The backend boundary is already two implementations deep, so a third is additive.

### T-054 — No vector output

Add PDF output that preserves text and paths as vectors and embeds raster content at source
resolution. This is the vector target needed by printing.

- Related: T-201, T-202, T-238, T-047

### T-201 — No SVG output

Serialize supported painter content to SVG with explicit fallback behavior for effects and raster
operations that have no direct representation.

- Related: T-054, T-186

### T-202 — No PostScript output

Add PostScript only as a separately justified output backend; it must not be hidden inside PDF
completion.

- Related: T-054

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
media stack. If `sCapture` ever records video, that belongs in its own module.
