# Pixel Backlog

This backlog covers the module-wide rendering, effects, image transformations, surface,
texture-sampling, vector-output, and geometry contracts of `std/pixel`. Image decoding, encoding,
metadata, multi-image input, and SVG decoding live in [std.pixel.image.md](std.pixel.image.md).

Evidence, investigations, and intended outcomes owned by `bin/std/modules/pixel` stay together in
these two scopes. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). Font parsing and shaping belongs in
[std.truetype.md](std.truetype.md). Platform renderer selection belongs in
[platform.portability.md](platform.portability.md). [README.md](README.md) has the whole layout.

Entries are ordered from the most recently updated down. An entry disappears when it
ships; history lives in Git, not here.

## Where the module already stands

Pixel provides CPU and OpenGL backends over one recorded painter command stream,
with command goldens and CPU rendering tests. Its painter has a full state stack, affine
transforms, clipping rectangles and boolean regions, render targets, layers, artistic blend modes,
custom OpenGL shaders, and integrated DPI content scale. Computational geometry includes boolean
polygon operations, offsetting, Delaunay triangulation, and painter fill/stroke tessellation;
math typesetting and distance-field text are integrated rendering families.

The module-wide gaps are explicit color semantics, high-quality texture sampling, portable vector
output, path measurement and effects, and the modern renderer choice tracked by
[platform.portability.066](platform.portability.md#platformportability066--renderer-backend-choice-has-no-target-matrix).

## Entries

### std.pixel.021 — Nothing reaches the unordered-intersection path

- Recorded: 2026-09-03 20:15
- Updated: 2026-09-12 10:02 — clarified this identifier's retired and current meanings
- Historical identifier provenance: `7cf248ed7` retired this identifier's OpenGL parity-readback
  entry. `d2f7ec754` reused it for polygon intersection cleanup; its current meaning is the
  remaining coverage investigation for the unordered-intersection path.
- Evidence: `Transform.processIntersections` in `poly/clipper.swg` now releases the nodes of a
  scanbeam whose intersections cannot be ordered, abandons the sweep, and returns an empty
  solution, which is what the reference library reports as a failed operation. No fixture reaches
  that branch, so the choice is argued rather than pinned, and neither the release nor the
  abandonment is covered.
- Next: build the input. The ordering failure needs three or more edges meeting so closely that
  no adjacent pair remains in the sorted edge list, which the union of near-coincident contours
  produces; drive `fixupIntersectionOrder` from a probe until it answers false, then reduce.
- Complete when: a test in `poly.clipper.test.swg` reaches the branch and pins the empty
  solution, or the branch is shown to be unreachable and says so.
- Related: std.pixel.011

### std.pixel.026 — Stroking a page costs four times filling the same geometry

- Recorded: 2026-08-30 17:42
- Updated: 2026-09-12 06:31 — Move painter stroke tessellation from the PDF consumer to Pixel.
- Intent: a fill keeps its tessellation inside the contour it filled, so a page drawn again only
  appends vertices. A stroke keeps nothing: every frame rebuilds a quad per segment and, between
  each pair of them, a join — two triangles and an antialiasing band along each of its outer
  edges. Eighteen vertices for the join against six for the segment it bridges, on a contour
  flattened from a curve where every turn is shallow.
- Historical provenance: moved from retired std.gui.pdf.035.
- Evidence: the historical comparison measured against a CPU renderer in release configuration, timing `drawPageItems`
  alone, best of twenty-five warm frames on an idle machine. A page of 3 300 glyph-sized marks —
  5 000 contours, 132 000 points, the shape a document that draws every glyph through a form of
  its own produces — records in 8.9 ms filled and 39 to 46 ms stroked. Removing every join takes
  the stroked page from 6.0 to 3.3 times the filled one, and to 1.8 times when the segments also
  measure their coverage from the centre line, so the join alone is about half of a stroke's
  recording.
- Note: two shortcuts were measured and rejected. Skipping a join whose outer corners fall closer
  than a tenth of a device pixel — which a minified pass already does — scallops every rounded
  corner at normal scale, because a curve's corner is a run of such turns and dropping all of them
  leaves the outer side unjoined; four focus-ring goldens and two stroke goldens caught it, with
  channel differences up to 235. Drawing a page's strokes under
  [[Pixel.PaintParams.DistanceStrokes]], as the SVG renderer does, was worth 7% of a stroked
  page's recording and moved 0.08% to 0.9% of a rendered page's pixels, by up to a full channel:
  the ink of a document is not ours to trade for that.
- Next: lay a contour's stroke down as one mitered ribbon rather than a quad per segment and a
  join between them, the way [[Pixel.Painter.fillPath]]'s antialiasing band already shares its
  mitered corners between adjacent edges. A turn past the miter limit still needs a join; every
  other turn stops needing one.
- Complete when: stroking a page costs the same order as filling the same contours, and a page of
  a few thousand stroked marks records in single-digit milliseconds on a warm cache.
- Related: std.gui.pdf.030, std.pixel.020

### std.pixel.027 — Dynamically registered typefaces cannot be released before module shutdown

- Recorded: 2026-08-18 14:15
- Updated: 2026-09-12 06:31 — Move the process-wide typeface lifetime contract to its Pixel owner.
- Historical provenance: moved from retired std.gui.pdf.027.
- Evidence: `TypeFace.create` and `load` return process-cache-owned pointers valid until module
  shutdown, with no unregister operation. PDF pages borrow those pointers; their embedded font
  program keys are already cached. Opening unrelated documents can grow the table for the
  process lifetime, even after their page caches close.
- Next: define releasable registration ownership alongside existing borrowed process-cache
  pointers. Account for renderer glyph caches and shared users before giving a document a
  release operation; never invalidate a pointer covered by the current lifetime contract.
- Complete when: dynamically registered faces can be reclaimed after their final owner releases
  them, cached glyph resources cannot retain stale pointers, and repeated PDF open/close tests
  show bounded growth while existing process-lifetime callers retain their documented behavior.
- Related: std.gui.pdf.028, std.gui.pdf.037

### std.pixel.019 — Image pipelines always materialize full intermediates

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-10 20:44 — grounded the remaining contract in the current eager and painter APIs
- Evidence: image operations mutate a complete owned buffer and use a complete working image.
  `Image.workingBuffer` and the eager crop/resize/filter implementations have no region producer
  or streaming sink, so even a local operation requires whole-image storage.
- Next: measure real large-image consumers, then design a read-only region producer and streaming
  sink for the subset of local operations that can be tiled; keep global analyses such as
  `smartcrop` explicitly separate.
- Complete when: a crop/resize/color pipeline over an image larger than RAM has bounded measured
  peak memory, deterministic edge halos, parallel tile execution, and the same output as the eager
  path within stated tolerance.
- Related: std.pixel.image.038, std.pixel.image.039

### std.pixel.014 — No composable transform effect node

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-10 20:44 — grounded the remaining contract in the current eager and painter APIs
- Evidence: painter transforms affect drawing state and eager image transforms materialize pixels;
  neither provides an affine node that consumes another effect result with explicit sampling,
  cropping, and tiling.
- Next: make translation the first case of an affine transform node, with crop and tile policy in
  options rather than separate hard-wired evaluation paths.
- Complete when: an input can be translated, scaled, rotated, cropped, and tiled while bounds and
  sampling remain deterministic on both renderers.
- Related: std.pixel.012, std.pixel.004, app.capture.004

### std.pixel.025 — GPU parity needs an explicit desktop integration boundary

- Recorded: 2026-09-07 11:24
- Updated: 2026-09-07 18:27 — removed native-window tests from the headless campaign at the owner's request
- Evidence: the former CPU/OpenGL parity helper created a real Windows window. Commit
  `00b430142` showed and pumped it to establish its drawable; `ea526b10e` later moved it off
  screen instead of removing the desktop dependency. The health reset reproduced corrupt or
  empty stroke images in JIT and native runs, including on a newly created, never displayed
  desktop. Matching clear/draw parameters, complete framebuffers, and successful independent
  OpenGL controls did not establish a renderer root cause.
- Current boundary: ordinary module tests now retain CPU rendering assertions and goldens,
  without creating native windows for GPU parity. This is an explicit scope correction, not
  evidence that the OpenGL renderer was repaired. The removed harness and investigations remain
  in Git and the campaign reports.
- Next: design a separately invoked GPU integration campaign with an explicit usable-desktop
  prerequisite, a fully realized window and message loop, and context lifecycle coverage. It
  must stay outside headless tests and must compare the first render without retries.
- Complete when: the explicit integration boundary detects context/rendering regressions in both
  program configurations without making an ordinary headless campaign create native windows.

### std.pixel.020 — Measured strokes are not yet what an ordinary stroke does

- Recorded: 2026-09-01 08:39
- Updated: 2026-09-07 18:27 — corrected stroke coverage after removing native-window parity tests
- What exists: `PaintParams.DistanceStrokes` makes a segment one quad carrying the signed distance
  to its centre line, which both backends turn into coverage the same way — the value travels in
  the ordinary coverage attribute, told apart from a band's ramp by sitting around
  `StrokeCoverageBias`, so measured segments and banded joins and caps still draw in one batch.
  `render.parity.test.swg` pins the software rasterizer with a golden over widths above and below
  a device pixel, every join and cap style, a curve, a dash and a transform. GPU parity requires
  the explicit desktop integration boundary in std.pixel.025.
  `Svg.Drawing.paintImpl` turns it on, so both ways of drawing a document — a viewport painted
  small and the same drawing rasterized whole — stay the same picture.
- What it bought (2026-09-01, release, Swag Scope showing a 1724 by 15036 document on a maximized
  3894x2142 window): 4.53 million vertices a frame down to 1.76, the frame from 112 ms to 74, and
  the adapter's share of it from 18 ms to half of one. Weight is unchanged to a third of a percent,
  measured as ink over the drawing. The theme's icons are rasterized through the same path: 39
  goldens moved, none by more than 0.96 % of its pixels, all of it edge coverage.
- What is left. A segment is measured; **a join, a cap and a dash cap still emit a quad and a band
  per edge**, which is most of what a stroke costs once joins are not being skipped — the minified
  pass skips them, which is why a document gains so much and a widget gains nothing yet. Giving
  them the same signed distance is the rest of this entry: a join is a wedge whose distance runs
  from its pivot, a cap a half disc or a square around one, and both are affine per triangle.
- Then the flag can be weighed as a default for every stroke. What decides it is a look, not a
  number: a band pair carries a solid core out to the full half width and softens beyond it, while
  the distance places the contour there and softens across it. On minified content the two are
  within a third of a percent of the same ink; on a widget's one-pixel rule at its own size they
  will not be, and that is the comparison to make before flipping it.
- Complete when: a stroke emits a constant small number of vertices per segment *and* per join, the
  two backends still agree, and `DistanceStrokes` is either the default or has a written reason not
  to be.
- Related: std.pixel.008

### std.pixel.022 — Measure whether the clipper should join contours during the sweep

- Recorded: 2026-09-06 17:42
- Evidence: `poly/clipper.swg` follows Clipper 6.4.2 and defers contour stitching to
  `joinCommonEdges`, `joinPoints` and `joinHorz`. The corrected `joinHorz` predicate in
  `d2f7ec754` and the later overlap correction were both in that post-pass. The file retains
  reference-compatible internals so comparisons remain possible.
- Next: instrument the join post-pass on a real document page and the existing glyph/overlapping
  polygon workloads. Establish its share of work before evaluating an in-sweep joining design.
  Preserve degenerate contours, holes and fill-rule behavior in any reduced prototype.
- Complete when: the joining strategy is either changed with behavioral parity and measured
  benefit, or retained for a measured reason. Intersection-discovery complexity is a separate lead.
- Related: std.pixel.011, std.pixel.021, std.pixel.024

### std.pixel.024 — No workload establishes the clipper intersection sort's worst-case cost

- Recorded: 2026-09-04 06:42
- Updated: 2026-09-06 17:42 — git: Add unit tests for float to u64 conversion safety checks
- Evidence: `Transform.buildIntersectList` discovers crossings with a bubble sort of the active
  edge list. Historical exact counters recorded 1.16 passes per scanbeam for glyph offsets and
  2.65 for forty overlapping 40-gons. These nearly sorted workloads do not establish whether a
  more general sort would pay for itself.
- Next: reduce a valid contour set that drives quadratic intersection discovery and measure its
  prevalence among filled vector-art consumers. Compare work counts and peak storage against a
  replacement without losing the existing nearly sorted fast case.
- Complete when: a representative worst-case fixture justifies and protects a change, or the
  current algorithm is retained with a documented bound for the supported workload.
- Related: std.pixel.022, std.pixel.021

### std.pixel.011 — Painter paths cannot use polygon boolean operations

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-03 09:34 — git: Cut PDF marks to the shape of their clip, and blend onto the window over an opaque backdrop
- Evidence: `poly/` has boolean operations, but `LinePathList` callers have no supported conversion
  with a shared tolerance, fill rule, scale, and failure contract. `LinePathList.intersect` is the
  one operation exposed so far, for the PDF decoder's nested clips: it takes two already-flattened
  lists and a fill rule for each, and answers a normalized polygonal list.
- Next: define conversion in both directions and expose union, difference, and xor beside the
  intersection at the painter-path boundary.
- Complete when: curved, holed, touching, self-intersecting, empty, and large-coordinate fixtures
  state their approximation and fill behavior and no caller reimplements flattening.
- Related: std.pixel.008, std.pixel.009

### std.pixel.004 — Painter texture sampling stops at nearest and bilinear

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-03 06:44 — git: Implement soft mask support in PDF rendering
- Evidence: `InterpolationMode` has only `Pixel` and `Linear`; generic textures have no mip chain,
  cubic reconstruction, anisotropic policy, or explicit edge mode. Minified or oblique content
  therefore aliases, while large magnification cannot select a higher-quality reconstruction.
- Evidence: a document page is where this is worst, because a photograph is placed at whatever size
  the page chose. A 2382x3071 illustration drawn over 350 points, rendered at 1.5 pixels per point,
  is a four-and-a-half-to-one minification: bilinear reads four texels of the twenty under each
  pixel. Against MuPDF over the same page, that page's mean absolute channel difference is 6.6 and
  0.45% of its pixels differ by more than 96 — visible as a moiré across the fine brushwork, where
  the pages with no photograph on them differ by antialiasing alone. Selecting `Linear` over the
  `Pixel` default took that page from 7.4 and 0.73%, so the remaining half of the gap is the
  missing prefilter rather than the reconstruction.
- Next: define sampling as a value contract separating reconstruction filter, mip selection, and
  edge behavior; implement one CPU/GPU cubic mode and mipmapped linear minification before
  considering anisotropy.
- Complete when: scale-up, scale-down, tiled edges, and oblique-transform fixtures select the same
  declared sampler on both backends, and mip use has measured aliasing and memory behavior.
- Related: std.pixel.014, std.pixel.image.041, std.pixel.image.042

### std.pixel.001 — Images and rendering have no color-space contract

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
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

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: float and 16-bit images can store values precisely, but painter targets remain RGBA8
  and no image, texture, or display surface can declare Display P3 or Rec.2020 primaries.
- Next: make wide-gamut image/texture/render-target formats and output conversion part of the
  renderer capability contract.
- Complete when: Display P3 content retains out-of-sRGB colors through load, effects, composition,
  and presentation on a capable surface, with a defined conversion on an sRGB surface.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.003, platform.portability.066

### std.pixel.003 — No HDR presentation and tone-mapping path

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: half/full-float CPU images retain extended values, but render targets are RGBA8 and no
  API carries transfer function, reference white, mastering/content-light metadata, display
  capability, or tone-map policy. Direct2D's advanced-color sample uses an FP16 pipeline and
  explicit display adaptation.
- Next: define scRGB/PQ/HLG representation boundaries, scene/display luminance units, FP16 surface
  capabilities, metadata ownership, and HDR-to-SDR fallback before choosing a tone mapper.
- Complete when: an HDR fixture reaches a capable display without clipping, produces a stable SDR
  rendering through an explicit tone mapper, and never silently treats encoded PQ as linear RGB.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.002, std.pixel.image.026

### std.pixel.012 — No public image-filter graph

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
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

- Recorded: 2026-08-09 11:49
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: `Layer.applyBlur` and `Painter.setBlurShader` cannot consume another graph node or
  publish their result to multiple consumers.
- Next: implement a separable blur node over std.pixel.012 with declared edge and crop behavior.
- Complete when: blur composes with offset, blend, and merge, propagates its expanded bounds, and
  CPU/OpenGL parity covers transparent edges and large radii.
- Related: std.pixel.012, app.capture.004

### std.pixel.015 — No composable color-matrix effect node

- Recorded: 2026-08-09 11:49
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: eager image filters change individual channels, but no rendered input can receive a
  4x5 RGBA matrix inside an effect graph.
- Next: add the node with explicit straight/premultiplied and working-space behavior.
- Complete when: the node represents saturation, grayscale, channel exchange, tint, and alpha
  scaling without special cases, and agrees on CPU and GPU in the chosen working space.
- Related: std.pixel.012, std.pixel.001

### std.pixel.016 — No composable blend effect node

- Recorded: 2026-08-09 11:49
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: painter blend modes combine a new draw with the active target; they cannot combine two
  named effect results without caller-managed render targets.
- Next: expose two graph inputs, the painter's complete artistic blend family, and a clear input
  order and alpha contract.
- Complete when: every portable painter blend mode combines two graph branches with parity and
  color-space tests.
- Related: std.pixel.012, std.pixel.001

### std.pixel.017 — No composable merge effect node

- Recorded: 2026-08-09 11:49
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: callers must currently build an ordered source-over merge as a chain of manual layers
  or pairwise blends.
- Next: add an ordered variadic graph node with empty and single-input semantics.
- Complete when: zero, one, and many inputs have specified bounds and ownership, and a shared input
  is evaluated once even when several merge branches reference it.
- Related: std.pixel.012

### std.pixel.018 — The effect baseline stops before masks and spatial filters

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
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

### std.pixel.005 — No painter-native PDF output

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: the PDF writer lives above Pixel in `std/gui` and cannot consume an arbitrary painter
  recording while preserving paths and text.
- Next: decide whether to move that writer below both consumers or implement a painter command
  visitor over it; do not create a second unrelated PDF serializer.
- Complete when: supported paths, text, clipping, transforms, and raster images remain native PDF
  objects, unsupported effects have a documented raster fallback, and printing no longer depends
  on GUI internals.
- Related: std.pixel.006, std.pixel.007, app.capture.001, std.gui.030

### std.pixel.006 — No arbitrary painter-to-SVG output

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: `Svg.Document` serializes its own narrow shape model, not a completed painter command
  stream containing text, clips, layers, textures, and blend modes.
- Next: define a painter recording visitor and explicit vector/raster fallback policy shared with
  PDF where the formats permit it.
- Complete when: portable painter commands serialize to SVG with preserved vector geometry and
  text, and unsupported operations rasterize only their minimal affected bounds.
- Related: std.pixel.005

### std.pixel.007 — No PostScript output

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: printing targets may still require PostScript, but neither the PDF writer nor Pixel has
  such a surface.
- Next: validate an actual consumer and target before committing an implementation; if justified,
  define it as a distinct backend over the same recording visitor.
- Complete when: either a named target proves unnecessary and the entry is removed, or that target
  receives a conforming document with explicit raster fallbacks.
- Related: std.pixel.005

### std.pixel.008 — No path trimming effect

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: dashing exists, but a caller cannot retain only a normalized or absolute arc-length
  interval of a path for reveal animation, progress strokes, or motion graphics.
- Next: implement trimming over the public measurement contract from std.pixel.009, including
  wrapped and closed intervals.
- Complete when: line, quadratic, cubic, arc, multi-contour, closed, empty, and wrapped paths trim
  with stated tolerance and preserve contour direction.
- Related: std.pixel.009, std.pixel.010, std.pixel.011

### std.pixel.009 — No public path measurement

- Recorded: 2026-09-01 08:20
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: flattening computes private segment geometry, but callers cannot obtain total length or
  sample a point and tangent at distance.
- Next: expose an immutable measurement object or operation with declared flattening tolerance and
  contour selection.
- Complete when: total length and clamped point/tangent sampling cover every segment kind, empty and
  zero-length contours, and repeated sampling does not re-flatten the path.
- Related: std.pixel.008

### std.pixel.010 — No corner path effect

- Recorded: 2026-08-09 11:30
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: rounded rectangles are primitives, but arbitrary polyline/path corners cannot be
  replaced by tangent arcs before stroking or filling.
- Next: define radius clamping, open/closed contour behavior, and curve-corner policy, then produce
  a new path without mutating the source.
- Complete when: acute, obtuse, short-edge, open, closed, and self-intersecting fixtures have stable
  geometry and preserve winding where defined.
- Related: std.pixel.008, std.pixel.009

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
