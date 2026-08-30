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

- **Codecs**: thirteen decoders and twelve encoders — BMP, DDS, EXR, GIF, ICO, JPEG including
  progressive, KTX2, PNG, PSD import, QOI, TGA, TIFF, and WebP with both the lossless and VP8 paths.
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

### pixel.image.002 — No image filter graph

- Problem: blur exists only as a painter shader (`setBlurShader`), applied to what is being drawn.
  There is no graph that applies a composable effect to a rendered result or chains effect output
  into another effect.
- Consequence: the standard way to build a shadow, a glow, a duotone, or a saturation adjustment
  over arbitrary content is unavailable. `image/filter/` operates on an `Image` in memory, which is
  not the same tool.
- Fix the graph evaluation, render-target lifetime, bounds propagation, caching, and composition
  contract independently of its concrete effect nodes.
- Related: pixel.image.003, pixel.image.004, pixel.image.005, pixel.image.006, pixel.image.007

### pixel.image.003 — No composable blur effect node

Apply blur to a rendered input inside pixel.image.002's graph, independently of the painter's draw-time blur
shader.

- Related: pixel.image.002, app.capture.004

### pixel.image.004 — No composable offset effect node

Translate an effect input while correctly expanding and propagating its bounds.

- Related: pixel.image.002, app.capture.004

### pixel.image.005 — No composable color-matrix effect node

Apply a declared color matrix inside the graph with the working-space behavior coordinated with
pixel.image.018.

- Related: pixel.image.002, pixel.image.018

### pixel.image.006 — No composable blend effect node

Blend two graph inputs using the painter's artistic blend modes and pixel.image.018's color-space contract.

- Related: pixel.image.002, pixel.image.018

### pixel.image.007 — No composable merge effect node

Merge an ordered set of graph inputs without requiring them to be blended pairwise by callers.

- Related: pixel.image.002

## Tier A — SVG input fidelity

### pixel.image.008 — SVG gradient geometry is incomplete

- Linear and centered radial paint servers, stops, spreads, percentages, user-space units and
  translate/scale gradient transforms are parsed. Radial focal points and non-square
  object-bounding-box ellipses still need a brush representation that both renderers share.
- Gradient inheritance resolves an already parsed `href`; forward inheritance chains and cycles
  still need a deferred resolver with explicit invalid-reference behavior.
- Related: pixel.image.009, pixel.image.011, pixel.image.012

### pixel.image.009 — SVG clipping paths are not parsed

Implement `clipPath` over the existing painter clipping facilities.

- Related: pixel.image.002, pixel.image.008, pixel.image.010

### pixel.image.010 — SVG masks are not parsed

Implement `mask` as a compositing operation over render targets independently of clipping paths.

- Related: pixel.image.002, pixel.image.008, pixel.image.009

### pixel.image.011 — SVG markers are not parsed

Implement start, mid, and end markers with correct path tangent orientation.

- Related: pixel.image.008, pixel.image.033

### pixel.image.012 — SVG symbols are not parsed

Implement `symbol` instancing and viewport behavior independently of ordinary `use` references.

- Related: pixel.image.008

---

## Tier B — Colour management and display range

### pixel.image.018 — No colour management

- Nothing in the API distinguishes sRGB from linear. Declare the working space and transfer
  behavior in images, brushes, blending, filters, and surfaces.
- The consequence is not only missing features. Compositing non-linear sRGB values directly is the
  standard cause of gradients and antialiased edges reading darker than they should — so this is a
  fidelity question, not a checkbox. Skia and Direct2D both take a position on it; this module
  takes none, which means the caller cannot take one either.
- Related: pixel.image.019, pixel.image.020, pixel.image.021

### pixel.image.019 — No ICC profile handling

Read, preserve, and convert embedded ICC profiles independently of choosing the default working
space.

- Related: pixel.image.018

### pixel.image.020 — No wide-gamut surface contract

Let images and surfaces declare a wide-gamut space such as Display P3 and convert to it correctly.

- Related: pixel.image.018, pixel.image.019, pixel.image.021

### pixel.image.021 — No HDR output path

Define HDR surface formats, transfer functions, luminance metadata, and tone-mapping boundaries.

- Related: pixel.image.020

---

## Tier C — Rendering backends and vector output


### pixel.image.022 — No vector output

Add PDF output that preserves text and paths as vectors and embeds raster content at source
resolution. This is the vector target needed by printing.

- Note: the repository's PDF writer lives in `std/gui` (`gui/src/controls/pdf/encode.swg`), above
  this module. Taking this entry up means either moving that writer below both consumers or
  growing a painter-native one here; do not duplicate it silently.
- Related: pixel.image.023, pixel.image.024, app.capture.001, std.gui.030

### pixel.image.023 — No SVG output

Serialize supported painter content to SVG with explicit fallback behavior for effects and raster
operations that have no direct representation.

- Related: pixel.image.022, pixel.image.008

### pixel.image.024 — No PostScript output

Add PostScript only as a separately justified output backend; it must not be hidden inside PDF
completion.

- Related: pixel.image.022

## Tier C — Image and texture codecs

### pixel.image.026 — No AVIF codec

Add AVIF decoding and encoding as its own dependency and color-management decision.

- Related: pixel.image.018

### pixel.image.027 — No JPEG XL codec

Add JPEG XL decoding and encoding independently of AVIF.

### pixel.image.028 — No DDS texture container

Read and write DDS metadata and supported block-compressed payloads without coupling it to KTX2.

- Related: platform.portability.066, pixel.image.029

### pixel.image.029 — No KTX2 texture container

Read and write KTX2 and define which GPU-compressed formats can remain compressed through upload.

- Related: platform.portability.066, pixel.image.028

## Tier C — Geometry and font resources

### pixel.image.032 — Path effects

Dashing exists. Add path trimming by normalized or absolute arc-length ranges.

- Related: pixel.image.033, pixel.image.034, pixel.image.035

### pixel.image.033 — No public path arc-length measurement

Expose total length and point/tangent sampling with stated flattening tolerance.

- Related: pixel.image.032, pixel.image.011

### pixel.image.034 — No corner path effect

Add a corner-rounding effect independently of trimming and measurement.

- Related: pixel.image.032

### pixel.image.035 — Painter paths cannot use polygon boolean operations

Define the conversion and tolerance contract that makes `poly/` boolean operations available to a
painter path.

- Related: pixel.image.032


---

## Out of scope

**A scene graph or a retained-mode API.** `pixel` is an immediate-mode painter plus an imaging
library, and `gui` owns the retained tree above it. Do not grow a second one here.

**Video decoding.** The WebP VP8 decoder exists because WebP needs it, not as the beginning of a
media stack. If `Swag Capture` ever records video, that belongs in its own module.
