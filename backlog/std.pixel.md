# Pixel Backlog

This backlog covers the module-wide rendering, effects, image transformations, surface,
texture-sampling, vector-output, and geometry contracts of `std/pixel`. Image decoding, encoding,
metadata, multi-image input, and SVG decoding live in [std.pixel.image.md](std.pixel.image.md).

Evidence, investigations, and intended outcomes owned by `bin/std/modules/pixel` stay together in
these two scopes. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). Font parsing and shaping belongs in
[std.truetype.md](std.truetype.md). Platform renderer selection belongs in
[platform.portability.md](platform.portability.md). [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in Git, not here.

## Where the module already stands

Pixel provides deterministic CPU and OpenGL backends over one recorded painter command stream,
with command goldens and renderer-parity tests. Its painter has a full state stack, affine
transforms, clipping rectangles and boolean regions, render targets, layers, artistic blend modes,
custom OpenGL shaders, and integrated DPI content scale. Computational geometry includes boolean
polygon operations, offsetting, Delaunay triangulation, and painter fill/stroke tessellation;
math typesetting and distance-field text are integrated rendering families.

The module-wide gaps are explicit color semantics, high-quality texture sampling, portable vector
output, path measurement and effects, and the modern renderer choice tracked by
[platform.portability.066](platform.portability.md#platformportability066--renderer-backend-choice-has-no-target-matrix).

## Tier A — Color management and display range

### std.pixel.001 — Images and rendering have no color-space contract

- Evidence: `PixelFormat` describes channels and precision but not primaries or transfer function.
  Brushes, gradients, blending, interpolation, filters, textures, render targets, and surfaces
  therefore cannot distinguish sRGB-encoded values from linear-light values.
- Next: define immutable color-space identity, default assumptions, conversion points, and the
  working space for every operation family before adding profile parsing.
- Complete when: an image and a surface each declare their color space, conversion is explicit,
  linear-light and encoded-space operations are intentionally distinguished, and CPU/GPU fixtures
  catch dark-edge and gradient errors.
- Related: std.pixel.015, std.pixel.016, std.pixel.image.019, std.pixel.002, std.pixel.003

### std.pixel.002 — No wide-gamut surface contract

- Evidence: float and 16-bit images can store values precisely, but painter targets remain RGBA8
  and no image, texture, or display surface can declare Display P3 or Rec.2020 primaries.
- Next: make wide-gamut image/texture/render-target formats and output conversion part of the
  renderer capability contract.
- Complete when: Display P3 content retains out-of-sRGB colors through load, effects, composition,
  and presentation on a capable surface, with a defined conversion on an sRGB surface.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.003, platform.portability.066

### std.pixel.003 — No HDR presentation and tone-mapping path

- Evidence: half/full-float CPU images retain extended values, but render targets are RGBA8 and no
  API carries transfer function, reference white, mastering/content-light metadata, display
  capability, or tone-map policy. Direct2D's advanced-color sample uses an FP16 pipeline and
  explicit display adaptation.
- Next: define scRGB/PQ/HLG representation boundaries, scene/display luminance units, FP16 surface
  capabilities, metadata ownership, and HDR-to-SDR fallback before choosing a tone mapper.
- Complete when: an HDR fixture reaches a capable display without clipping, produces a stable SDR
  rendering through an explicit tone mapper, and never silently treats encoded PQ as linear RGB.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.002, std.pixel.image.026

---

## Tier A — Composable image effects

### std.pixel.012 — No public image-filter graph

- Evidence: blur and shadow are layer operations, and SVG evaluates a private linear subset. There
  is no public DAG that applies effects to rendered content, shares an intermediate, or feeds one
  result to several consumers. Skia's filter contract recursively maps bounds through a DAG.
- Next: define graph inputs, immutable node ownership, bounds propagation, evaluation, temporary
  target lifetime, caching, color-space transitions, and backend fallback independently of the
  concrete node catalogue.
- Complete when: one graph can branch and rejoin, evaluates identically on CPU and GPU, allocates
  only propagated bounds, reuses unchanged intermediates, and cannot retain a dead render target.
- Related: std.pixel.013, std.pixel.014, std.pixel.015, std.pixel.016, std.pixel.017,
  std.pixel.001, std.pixel.018

### std.pixel.013 — No composable blur effect node

- Evidence: `Layer.applyBlur` and `Painter.setBlurShader` cannot consume another graph node or
  publish their result to multiple consumers.
- Next: implement a separable blur node over std.pixel.012 with declared edge and crop behavior.
- Complete when: blur composes with offset, blend, and merge, propagates its expanded bounds, and
  CPU/OpenGL parity covers transparent edges and large radii.
- Related: std.pixel.012, app.capture.004

### std.pixel.014 — No composable transform effect node

- Evidence: the current planned offset-only node would not cover the ordinary image-filter need to
  transform, crop, and tile an input with explicit sampling. Direct2D and Skia both expose general
  transform nodes.
- Next: make translation the first case of an affine transform node, with crop and tile policy in
  options rather than separate hard-wired evaluation paths.
- Complete when: an input can be translated, scaled, rotated, cropped, and tiled while bounds and
  sampling remain deterministic on both renderers.
- Related: std.pixel.012, std.pixel.004, app.capture.004

### std.pixel.015 — No composable color-matrix effect node

- Evidence: eager image filters change individual channels, but no rendered input can receive a
  4x5 RGBA matrix inside an effect graph.
- Next: add the node with explicit straight/premultiplied and working-space behavior.
- Complete when: the node represents saturation, grayscale, channel exchange, tint, and alpha
  scaling without special cases, and agrees on CPU and GPU in the chosen working space.
- Related: std.pixel.012, std.pixel.001

### std.pixel.016 — No composable blend effect node

- Evidence: painter blend modes combine a new draw with the active target; they cannot combine two
  named effect results without caller-managed render targets.
- Next: expose two graph inputs, the painter's complete artistic blend family, and a clear input
  order and alpha contract.
- Complete when: every portable painter blend mode combines two graph branches with parity and
  color-space tests.
- Related: std.pixel.012, std.pixel.001

### std.pixel.017 — No composable merge effect node

- Evidence: callers must currently build an ordered source-over merge as a chain of manual layers
  or pairwise blends.
- Next: add an ordered variadic graph node with empty and single-input semantics.
- Complete when: zero, one, and many inputs have specified bounds and ownership, and a shared input
  is evaluated once even when several merge branches reference it.
- Related: std.pixel.012

### std.pixel.018 — The effect baseline stops before masks and spatial filters

- Evidence: Direct2D's standard effect set includes alpha mask, convolution, morphology,
  displacement, transfer curves, and lighting. Pixel has eager `applyKernel`, but the planned graph
  covers only blur, transform, color matrix, blend, and merge; SVG also cannot model `in`, `in2`,
  named `result` values, `filterUnits`, or `primitiveUnits`.
- Next: after std.pixel.012 lands, rank the missing node families against SVG filters, capture
  effects, and image-editor consumers; commit only the smallest coherent v1 set and map SVG filter
  references onto the same DAG.
- Complete when: the v1 node matrix records support, fallback, bounds, and color behavior for CPU
  and GPU, and SVG no longer maintains a separate effect execution model.
- Related: std.pixel.012, std.pixel.image.010, std.pixel.001

---

---

## Tier B — Bounded image processing

### std.pixel.019 — Image pipelines always materialize full intermediates

- Evidence: image operations mutate a complete owned buffer and use at most one complete working
  image. In contrast, libvips joins demand-driven region producers, keeps only active tiles in RAM,
  and streams the sink; image size and pipeline length do not multiply peak memory.
- Next: measure real large-image consumers, then design a read-only region producer and streaming
  sink for the subset of local operations that can be tiled; keep global analyses such as
  `smartcrop` explicitly separate.
- Complete when: a crop/resize/color pipeline over an image larger than RAM has bounded measured
  peak memory, deterministic edge halos, parallel tile execution, and the same output as the eager
  path within stated tolerance.
- Related: std.pixel.image.038, std.pixel.image.039

---

---
## Tier B — Texture sampling fidelity

### std.pixel.004 — Painter texture sampling stops at nearest and bilinear

- Evidence: `InterpolationMode` has only `Pixel` and `Linear`; generic textures have no mip chain,
  cubic reconstruction, anisotropic policy, or explicit edge mode. Minified or oblique content
  therefore aliases, while large magnification cannot select a higher-quality reconstruction.
- Next: define sampling as a value contract separating reconstruction filter, mip selection, and
  edge behavior; implement one CPU/GPU cubic mode and mipmapped linear minification before
  considering anisotropy.
- Complete when: scale-up, scale-down, tiled edges, and oblique-transform fixtures select the same
  declared sampler on both backends, and mip use has measured aliasing and memory behavior.
- Related: std.pixel.014, std.pixel.image.041, std.pixel.image.042

---

## Tier C — Vector output

### std.pixel.005 — No painter-native PDF output

- Evidence: the PDF writer lives above Pixel in `std/gui` and cannot consume an arbitrary painter
  recording while preserving paths and text.
- Next: decide whether to move that writer below both consumers or implement a painter command
  visitor over it; do not create a second unrelated PDF serializer.
- Complete when: supported paths, text, clipping, transforms, and raster images remain native PDF
  objects, unsupported effects have a documented raster fallback, and printing no longer depends
  on GUI internals.
- Related: std.pixel.006, std.pixel.007, app.capture.001, std.gui.030

### std.pixel.006 — No arbitrary painter-to-SVG output

- Evidence: `Svg.Document` serializes its own narrow shape model, not a completed painter command
  stream containing text, clips, layers, textures, and blend modes.
- Next: define a painter recording visitor and explicit vector/raster fallback policy shared with
  PDF where the formats permit it.
- Complete when: portable painter commands serialize to SVG with preserved vector geometry and
  text, and unsupported operations rasterize only their minimal affected bounds.
- Related: std.pixel.005

### std.pixel.007 — No PostScript output

- Evidence: printing targets may still require PostScript, but neither the PDF writer nor Pixel has
  such a surface.
- Next: validate an actual consumer and target before committing an implementation; if justified,
  define it as a distinct backend over the same recording visitor.
- Complete when: either a named target proves unnecessary and the entry is removed, or that target
  receives a conforming document with explicit raster fallbacks.
- Related: std.pixel.005

---

## Tier C — Geometry and path effects

### std.pixel.008 — No path trimming effect

- Evidence: dashing exists, but a caller cannot retain only a normalized or absolute arc-length
  interval of a path for reveal animation, progress strokes, or motion graphics.
- Next: implement trimming over the public measurement contract from std.pixel.009, including
  wrapped and closed intervals.
- Complete when: line, quadratic, cubic, arc, multi-contour, closed, empty, and wrapped paths trim
  with stated tolerance and preserve contour direction.
- Related: std.pixel.009, std.pixel.010, std.pixel.011

### std.pixel.009 — No public path measurement

- Evidence: flattening computes private segment geometry, but callers cannot obtain total length or
  sample a point and tangent at distance.
- Next: expose an immutable measurement object or operation with declared flattening tolerance and
  contour selection.
- Complete when: total length and clamped point/tangent sampling cover every segment kind, empty and
  zero-length contours, and repeated sampling does not re-flatten the path.
- Related: std.pixel.008

### std.pixel.010 — No corner path effect

- Evidence: rounded rectangles are primitives, but arbitrary polyline/path corners cannot be
  replaced by tangent arcs before stroking or filling.
- Next: define radius clamping, open/closed contour behavior, and curve-corner policy, then produce
  a new path without mutating the source.
- Complete when: acute, obtuse, short-edge, open, closed, and self-intersecting fixtures have stable
  geometry and preserve winding where defined.
- Related: std.pixel.008, std.pixel.009

### std.pixel.011 — Painter paths cannot use polygon boolean operations

- Evidence: `poly/` has boolean operations, but `LinePathList` callers have no supported conversion
  with a shared tolerance, fill rule, scale, and failure contract.
- Next: define conversion in both directions and expose union, intersection, difference, and xor at
  the painter-path boundary.
- Complete when: curved, holed, touching, self-intersecting, empty, and large-coordinate fixtures
  state their approximation and fill behavior and no caller reimplements flattening.
- Related: std.pixel.008, std.pixel.009

### std.pixel.020 — A stroke segment costs about thirty-five vertices

- Evidence: a stroked polyline pays, per segment, a quad (six vertices), a fringe band on each of
  its two long edges (twelve), and a join carrying two fringes of its own (eighteen). A stroker
  that derives coverage in the fragment shader spends four to six. Recording is therefore bound by
  vertex emission, measured at fifteen to twenty nanoseconds per vertex and two to four times that
  once the working set leaves cache: a 1724 by 15036 SVG holding 250 000 stroke points records 2.5
  million vertices and about 110 ms of CPU for one full-document paint, strokes accounting for over
  90 % of it. Viewport rejection and the minified level of detail already removed a factor of five
  to three hundred depending on zoom; this is the density that remains for the content genuinely on
  screen.
- Measured again on a maximized 3894x2142 window (2026-09-01, release, Swag Scope showing that
  same document fitted to the window, so a 245 pixel wide column): one full-document repaint
  records **4.53 million vertices in 14 481 batches and costs 94 to 128 ms of processor time**.
  Disabling the stroke pass alone takes the same frame to 104 000 vertices and 9.4 ms, so
  **strokes are 98 % of the geometry and over 90 % of the recording**, with joins already skipped
  by the minified limits. The document is minified to about 0.14, and the decimation step is the
  flattening tolerance rather than the device grid — `setMinifiedStrokeLimits` uses
  `getFlattenDistance(quality) / curFlattenScale`, which at Normal quality drops points closer
  than 0.2 device pixels and so keeps roughly five contour points per device pixel. Raising that
  step trades outline fidelity for a proportional cut and is a quality decision, not a free one.
- The fringe is what to attack: `addEdgeAA` emits a whole quad per silhouette edge because the
  shaders read coverage from a vertex attribute. A stroke program given the segment and the half
  width, deriving coverage from the fragment's distance to the centre line, collapses a segment to
  its two triangles and removes the joins with it.
- Next: prototype a distance-based stroke program in `RenderCpu` and the OpenGL backend behind an
  opt-in painter flag, and pin the two against each other with `render.parity.test.swg` before it
  becomes the default.
- Complete when: an antialiased stroke emits a constant small number of vertices per segment, both
  backends agree on the result, and the painter recording goldens move once, deliberately.
- Related: std.pixel.008

---

## Out of scope

**Image codecs.** Decoding, encoding, metadata, multi-image containers, and SVG input are tracked
in [std.pixel.image.md](std.pixel.image.md).

**A retained scene graph.** `pixel` is an immediate/deferred painter plus an imaging library;
`gui` owns the retained tree. The image-effect DAG does not create a second UI hierarchy.

**Text shaping and font-format completion.** Pixel consumes positioned glyphs and owns painter text
caches, but GSUB/GPOS shaping, variable fonts, and color-glyph formats are tracked in
[std.truetype.md](std.truetype.md).

**A specific modern GPU backend chosen in isolation.** Pixel owns the renderer interface and parity
contract, but the next implementation must follow the operating-system and hardware matrix in
[platform.portability.066](platform.portability.md#platformportability066--renderer-backend-choice-has-no-target-matrix).
