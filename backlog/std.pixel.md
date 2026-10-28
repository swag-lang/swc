# Pixel Backlog

This backlog covers the module-wide rendering, effects, image transformations, surface,
texture-sampling, vector-output, and geometry contracts of `std/pixel`. Image decoding, encoding,
metadata, multi-image input, and SVG decoding live in [std.pixel.image.md](std.pixel.image.md).

Evidence, investigations, and intended outcomes owned by `bin/std/modules/pixel` stay together in
these two scopes. Compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). Font parsing and shaping belongs in
[std.truetype.md](std.truetype.md). Platform renderer selection belongs in
[platform.portability.md](platform.portability.md). [README.md](README.md) has the whole layout.

Entries stay in one flat list. Delete an entry when it
ships; history lives in Git, not here.

## Entries

### std.pixel.032 — `Image.setChannel` leaves straight RGBA8 pixels unchanged

- Evidence: on a straight `RGBA8` image, `setChannel(.RGB, .Color, 0xFF)` returns without
  changing a pixel (a keyed-out `0xFFF7F900` stays `0xFFF7F900`); only the BGR8/BGRA8 storage path
  writes. `image.simd.tail.test.swg` pins that: it expects the `setChannel` bytes to change for
  BGR8 and BGRA8 only. The other formats go through `transformLogicalPixels`; why the write is lost
  there is not established (the closure also shadows the method's own `value` parameter).
  `Application.loadAppIconCuts` whitens the window glyph with `visitPixels` instead.
- Next: reduce the generic path of `setChannel` to a standalone reproducer, find where the write is
  lost, fix it, and make the SIMD tail test expect the write in every format.
- Done when: `setChannel` writes the selected channels in every packed format and the tail test
  says so.

### std.pixel.011 — Painter paths cannot use polygon boolean operations

- Evidence: `poly/` has boolean operations, but `LinePathList` callers have no supported conversion
  with a shared tolerance, fill rule, scale, and failure contract. `LinePathList.clean` (a
  self-union and normalization) and `LinePathList.intersect` (for the PDF decoder's nested clips,
  taking a fill rule per list) are the only operations exposed; both take already-flattened lists
  and answer a normalized polygonal list.
- Next: define conversion in both directions and expose a two-operand union, difference, and xor
  beside the intersection at the painter-path boundary.
- Done when: curved, holed, touching, self-intersecting, empty, and large-coordinate fixtures
  state their approximation and fill behavior and no caller reimplements flattening.
- Related: std.pixel.008, std.pixel.009

### std.pixel.025 — Extend the explicit OpenGL campaign to the portable rendering scenes

- Evidence: `tools/integrations.swgs opengl` runs only tests tagged
  `integration.renderer.opengl`, in both configurations with `--all-cfg`. `sampling.ogl.test.swg`
  compares CPU and GPU texture sampling, and `renderthread.test.swg` checks a worker-owned
  context and render-target readback. The stroke, text and layer scenes in
  `render.parity.test.swg` run only against `RenderCpu` and its goldens. Stroke output has
  come back corrupt or empty under some drawable arrangements, so a hidden drawable alone does
  not establish coverage.
- Next: add the portable stroke, text and layer scenes to the named campaign together with a
  fully realized window/message-loop fixture. Compare the first render without retries and
  cover context creation, presentation and teardown on an explicitly usable desktop.
- Done when: those scenes and context transitions detect rendering regressions in both
  program configurations, and ordinary headless tests still create no native windows.
- Related: std.pixel.020

### std.pixel.020 — Measured strokes are not yet what an ordinary stroke does

- Evidence: under `PaintParams.DistanceStrokes` a stroke segment is one quad (`drawpath.swg`)
  carrying the signed distance to its centre line around `StrokeCoverageBias` (`painter.swg`),
  and both backends resolve it the same way. Joins, caps and dash caps still emit a quad plus an
  antialiasing band per edge through `drawJoin`/`drawJoinBevel`/`drawJoinRound`/`drawJoinMiter`,
  which is most of a stroke's cost once joins are not skipped. The flag is opt-in. Only
  `Svg.Drawing.paintImpl` enables it.
- Next: give joins and caps the same signed distance. A join is a wedge whose distance runs
  from its pivot, and a cap is a half disc or a square around it, both affine per triangle.
  Then compare a widget's one-pixel rule at native size with and without the flag before
  considering it as the default.
- Done when: a stroke emits a constant small number of vertices per segment and per join, the
  CPU and OpenGL backends still agree, and `DistanceStrokes` is either the default or has a
  written reason not to be.
- Related: std.pixel.008, std.pixel.025, std.pixel.026

### std.pixel.031 — Nothing reaches the unordered-intersection path

- Evidence: `Transform.processIntersections` in `poly/clipper.swg` releases the nodes of a
  scanbeam whose intersections cannot be ordered, abandons the sweep, and returns an empty
  solution, which is what the reference library reports as a failed operation. No fixture reaches
  that branch, so neither the release nor the abandonment is covered.
- Next: build the input. The ordering failure needs three or more edges meeting so closely that
  no adjacent pair remains in the sorted edge list, which the union of near-coincident contours
  produces; drive `fixupIntersectionOrder` from a probe until it answers false, then reduce.
- Done when: a test in `poly.clipper.test.swg` reaches the branch and pins the empty
  solution, or the branch is shown to be unreachable and says so.
- Related: std.pixel.011

### std.pixel.030 — Plain non-copy rectangles still use the general coverage shader

- Evidence: `Painter.fillRectRaw` emits fully covered, device-aligned triangles, but ordinary
  alpha-composited textures and solid widget backgrounds still execute `aa.frag`. That program
  computes coverage derivatives and samples the glyph-mask texture even for these rectangles.
  Replacing it blindly with `simple.frag` changes zero-alpha discard behavior in non-copy blend
  modes, and can override explicit blur, resolve, font, or custom programs.
- Next: measure these remaining batches separately from `Copy` blits, establish equivalence for
  each blend and clip-mask operation, then select the cheapest correct program centrally. Include
  the extra program switches in the cost rather than counting fragment instructions alone.
- Done when: the safe cases have a measured program-selection policy, transparent-texel and
  clip-mask regressions cover its boundaries, and native CPU/GPU comparisons preserve output.

### std.pixel.029 — OpenGL glyph atlases retain a complete CPU pixel copy

- Evidence: `GlyphAtlas.data` retains every bitmap/MSDF page after upload. `RenderCpu` samples
  those bytes directly. OpenGL now uploads the bounding rectangle of appended glyphs, but that
  rectangle can include existing pixels, and initial texture allocation still reads the full page.
- Next: measure retained atlas bytes in a long document session, then separate backend storage
  policy. Keep full pages for CPU rendering; investigate tightly packed pending-glyph buffers for
  OpenGL, with zero-initialized texture storage, bounded staging memory, and an explicit texture
  recreation strategy. Do not discard page bytes while rectangle uploads still depend on them.
- Done when: OpenGL releases uploaded staging pixels without changing bitmap/MSDF output,
  fallback fonts, mipmap padding, or context/resource lifetime; CPU rendering remains unchanged
  and the measured host-memory saving justifies the additional ownership machinery.

### std.pixel.028 — Fallback selection does not yet preserve shaping clusters

- Evidence: `Font.resolveRune` and `Painter.shapeRunInto` now resolve missing Unicode scalars,
  including supplementary-plane values, and preserve each glyph's face through measurement and
  drawing. The current shaper still emits one glyph per scalar: a base plus combining mark,
  a variation selector, or an emoji ZWJ sequence can require one fallback face for the whole
  cluster instead. Rune fallback alone neither performs those substitutions nor positions marks.
- Next: connect fallback selection to the shaping boundary decided in std.truetype.008. Try a
  face against a complete cluster, preserve source byte ranges, and define the unresolved-cluster
  policy alongside variation selectors and default-ignorable characters.
- Done when: combining-mark, variation-selector, and ZWJ fixtures retain cluster identity
  across fallback, shaping, selection, and bitmap/MSDF rebuilding.
- Related: std.truetype.008, std.truetype.009, std.truetype.016

### std.pixel.027 — Dynamically registered typefaces cannot be released before module shutdown

- Evidence: `TypeFace.create` and `load` return process-cache-owned pointers valid until module
  shutdown, with no unregister operation. PDF pages borrow those pointers; their embedded font
  program keys are already cached. Opening unrelated documents can grow the table for the
  process lifetime, even after their page caches close.
- Evidence: automatic system fallback also loads candidate faces into this process cache. A
  first unsupported scalar can visit every installed family; the rune result is cached, but
  candidate font programs remain retained even when none covers that scalar.
- Next: index character coverage without retaining every candidate font program, and define
  releasable registration ownership alongside existing borrowed process-cache pointers.
  Account for renderer glyph caches and shared users before giving a document a
  release operation; never invalidate a pointer covered by the current lifetime contract.
- Done when: dynamically registered faces can be reclaimed after their final owner releases
  them, cached glyph resources cannot retain stale pointers, and repeated PDF open/close tests
  show bounded growth while existing process-lifetime callers retain their documented behavior.
- Related: std.gui.pdf.028, std.gui.pdf.037

### std.pixel.026 — Stroking a page costs four times filling the same geometry

- Evidence: a fill keeps its tessellation, so a page drawn again only appends vertices. A
  stroke rebuilds every frame a quad per segment and a join between each pair, two triangles
  plus a band along each outer edge, which is eighteen vertices against six for the segment on
  a flattened curve. On a page of about 5 000 glyph-sized contours, stroking records several
  times slower than filling, and the joins are about half of a stroke's recording.
- Evidence: skipping sub-pixel joins at normal scale scallops rounded corners (focus-ring and
  stroke goldens catch it). Drawing document strokes under
  [[Pixel.PaintParams.DistanceStrokes]] saves little and changes document ink, so neither is
  acceptable.
- Next: lay a contour's stroke down as one mitered ribbon rather than a quad per segment plus
  joins, the way [[Pixel.Painter.fillPath]]'s antialiasing band shares mitered corners between
  adjacent edges. Only a turn past the miter limit keeps a join.
- Done when: stroking a page costs the same order as filling the same contours, and a page of
  a few thousand stroked marks records in single-digit milliseconds on a warm cache.
- Related: std.gui.pdf.030, std.pixel.020

### std.pixel.019 — Image pipelines always materialize full intermediates

- Evidence: image operations mutate a complete owned buffer and use a complete working image.
  `Image.workingBuffer` and the eager crop/resize/filter implementations have no region producer
  or streaming sink, so even a local operation requires whole-image storage.
- Next: measure real large-image consumers, then design a read-only region producer and streaming
  sink for the subset of local operations that can be tiled; keep global analyses such as
  `Image.smartCrop` explicitly separate.
- Done when: a crop/resize/color pipeline over an image larger than RAM has bounded measured
  peak memory, deterministic edge halos, parallel tile execution, and the same output as the eager
  path within stated tolerance.
- Related: std.pixel.image.038, std.pixel.image.039

### std.pixel.014 — No composable transform effect node

- Evidence: painter transforms affect drawing state and eager image transforms materialize pixels;
  neither provides an affine node that consumes another effect result with explicit sampling,
  cropping, and tiling.
- Next: make translation the first case of an affine transform node, with crop and tile policy in
  options rather than separate hard-wired evaluation paths.
- Done when: an input can be translated, scaled, rotated, cropped, and tiled while bounds and
  sampling remain deterministic on both renderers.
- Related: std.pixel.012, std.pixel.004, app.capture.004

### std.pixel.022 — Measure whether the clipper should join contours during the sweep

- Evidence: `poly/clipper.swg` follows Clipper 6.4.2 and defers contour stitching to
  `joinCommonEdges`, `joinPoints` and `joinHorz`, where past correctness defects were found.
  The file keeps reference-compatible internals so comparisons remain possible.
- Next: instrument the join post-pass on a real document page and the existing glyph/overlapping
  polygon workloads. Establish its share of work before evaluating an in-sweep joining design.
  Preserve degenerate contours, holes and fill-rule behavior in any reduced prototype.
- Done when: the joining strategy is either changed with behavioral parity and measured
  benefit, or retained for a measured reason. Intersection-discovery complexity is a separate lead.
- Related: std.pixel.011, std.pixel.031, std.pixel.024

### std.pixel.024 — No workload establishes the clipper intersection sort's worst-case cost

- Evidence: `Transform.buildIntersectList` discovers crossings with a bubble sort of the active
  edge list. Historical exact counters recorded 1.16 passes per scanbeam for glyph offsets and
  2.65 for forty overlapping 40-gons. These nearly sorted workloads do not establish whether a
  more general sort would pay for itself.
- Next: reduce a valid contour set that drives quadratic intersection discovery and measure its
  prevalence among filled vector-art consumers. Compare work counts and peak storage against a
  replacement without losing the existing nearly sorted fast case.
- Done when: a representative worst-case fixture justifies and protects a change, or the
  current algorithm is retained with a documented bound for the supported workload.
- Related: std.pixel.022, std.pixel.031

### std.pixel.004 — Painter texture sampling stops at nearest and bilinear

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
- Done when: scale-up, scale-down, tiled edges, and oblique-transform fixtures select the same
  declared sampler on both backends, and mip use has measured aliasing and memory behavior.
- Related: std.pixel.014, std.pixel.image.041, std.pixel.image.042

### std.pixel.001 — Images and rendering have no color-space contract

- Evidence: `PixelFormat` describes channels and precision but not primaries or transfer function.
  Brushes, gradients, blending, interpolation, filters, textures, render targets, and surfaces
  therefore cannot distinguish sRGB-encoded values from linear-light values.
- Next: define immutable color-space identity, default assumptions, conversion points, and the
  working space for every operation family before adding profile parsing.
- Done when: an image and a surface each declare their color space, conversion is explicit,
  linear-light and encoded-space operations are intentionally distinguished, and CPU/GPU fixtures
  catch dark-edge and gradient errors.
- Related: std.pixel.015, std.pixel.016, std.pixel.image.019, std.pixel.002, std.pixel.003

### std.pixel.002 — No wide-gamut surface contract

- Evidence: float and 16-bit images can store values precisely, but painter targets remain RGBA8
  and no image, texture, or display surface can declare Display P3 or Rec.2020 primaries.
- Next: make wide-gamut image/texture/render-target formats and output conversion part of the
  renderer capability contract.
- Done when: Display P3 content retains out-of-sRGB colors through load, effects, composition,
  and presentation on a capable surface, with a defined conversion on an sRGB surface.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.003, platform.portability.066

### std.pixel.003 — No HDR presentation and tone-mapping path

- Evidence: half/full-float CPU images retain extended values, but render targets are RGBA8 and no
  API carries transfer function, reference white, mastering/content-light metadata, display
  capability, or tone-map policy. Direct2D's advanced-color sample uses an FP16 pipeline and
  explicit display adaptation.
- Next: define scRGB/PQ/HLG representation boundaries, scene/display luminance units, FP16 surface
  capabilities, metadata ownership, and HDR-to-SDR fallback before choosing a tone mapper.
- Done when: an HDR fixture reaches a capable display without clipping, produces a stable SDR
  rendering through an explicit tone mapper, and never silently treats encoded PQ as linear RGB.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.002, std.pixel.image.026

### std.pixel.012 — No public image-filter graph

- Evidence: blur and shadow are layer operations, and SVG evaluates a private linear subset. There
  is no public DAG that applies effects to rendered content, shares an intermediate, or feeds one
  result to several consumers. Skia's filter contract recursively maps bounds through a DAG.
- Next: define graph inputs, immutable node ownership, bounds propagation, evaluation, temporary
  target lifetime, caching, color-space transitions, and backend fallback independently of the
  concrete node catalogue.
- Done when: one graph can branch and rejoin, evaluates identically on CPU and GPU, allocates
  only propagated bounds, reuses unchanged intermediates, and cannot retain a dead render target.
- Related: std.pixel.013, std.pixel.014, std.pixel.015, std.pixel.016, std.pixel.017,
  std.pixel.001, std.pixel.018

### std.pixel.013 — No composable blur effect node

- Evidence: `Layer.applyBlur` and `Painter.setBlurShader` cannot consume another graph node or
  publish their result to multiple consumers.
- Next: implement a separable blur node over std.pixel.012 with declared edge and crop behavior.
- Done when: blur composes with offset, blend, and merge, propagates its expanded bounds, and
  CPU/OpenGL parity covers transparent edges and large radii.
- Related: std.pixel.012, app.capture.004

### std.pixel.015 — No composable color-matrix effect node

- Evidence: eager image filters change individual channels, but no rendered input can receive a
  4x5 RGBA matrix inside an effect graph.
- Next: add the node with explicit straight/premultiplied and working-space behavior.
- Done when: the node represents saturation, grayscale, channel exchange, tint, and alpha
  scaling without special cases, and agrees on CPU and GPU in the chosen working space.
- Related: std.pixel.012, std.pixel.001

### std.pixel.016 — No composable blend effect node

- Evidence: painter blend modes combine a new draw with the active target; they cannot combine two
  named effect results without caller-managed render targets.
- Next: expose two graph inputs, the painter's complete artistic blend family, and a clear input
  order and alpha contract.
- Done when: every portable painter blend mode combines two graph branches with parity and
  color-space tests.
- Related: std.pixel.012, std.pixel.001

### std.pixel.017 — No composable merge effect node

- Evidence: callers must currently build an ordered source-over merge as a chain of manual layers
  or pairwise blends.
- Next: add an ordered variadic graph node with empty and single-input semantics.
- Done when: zero, one, and many inputs have specified bounds and ownership, and a shared input
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
- Done when: the v1 node matrix records support, fallback, bounds, and color behavior for CPU
  and GPU, and SVG no longer maintains a separate effect execution model.
- Related: std.pixel.012, std.pixel.image.010, std.pixel.001

### std.pixel.005 — No painter-native PDF output

- Evidence: the PDF writer lives above Pixel in `std/gui` and cannot consume an arbitrary painter
  recording while preserving paths and text.
- Next: decide whether to move that writer below both consumers or implement a painter command
  visitor over it; do not create a second unrelated PDF serializer.
- Done when: supported paths, text, clipping, transforms, and raster images remain native PDF
  objects, unsupported effects have a documented raster fallback, and printing no longer depends
  on GUI internals.
- Related: std.pixel.006, std.pixel.007, app.capture.001, std.gui.030

### std.pixel.006 — No arbitrary painter-to-SVG output

- Evidence: `Svg.Document` serializes its own narrow shape model, not a completed painter command
  stream containing text, clips, layers, textures, and blend modes.
- Next: define a painter recording visitor and explicit vector/raster fallback policy shared with
  PDF where the formats permit it.
- Done when: portable painter commands serialize to SVG with preserved vector geometry and
  text, and unsupported operations rasterize only their minimal affected bounds.
- Related: std.pixel.005

### std.pixel.007 — No PostScript output

- Evidence: printing targets may still require PostScript, but neither the PDF writer nor Pixel has
  such a surface.
- Next: validate an actual consumer and target before committing an implementation; if justified,
  define it as a distinct backend over the same recording visitor.
- Done when: either a named target proves unnecessary and the entry is removed, or that target
  receives a conforming document with explicit raster fallbacks.
- Related: std.pixel.005

### std.pixel.008 — No path trimming effect

- Evidence: dashing exists, but a caller cannot retain only a normalized or absolute arc-length
  interval of a path for reveal animation, progress strokes, or motion graphics.
- Next: implement trimming over the public measurement contract from std.pixel.009, including
  wrapped and closed intervals.
- Done when: line, quadratic, cubic, arc, multi-contour, closed, empty, and wrapped paths trim
  with stated tolerance and preserve contour direction.
- Related: std.pixel.009, std.pixel.010, std.pixel.011

### std.pixel.009 — No public path measurement

- Evidence: flattening computes private segment geometry, but callers cannot obtain total length or
  sample a point and tangent at distance.
- Next: expose an immutable measurement object or operation with declared flattening tolerance and
  contour selection.
- Done when: total length and clamped point/tangent sampling cover every segment kind, empty and
  zero-length contours, and repeated sampling does not re-flatten the path.
- Related: std.pixel.008

### std.pixel.010 — No corner path effect

- Evidence: rounded rectangles are primitives, but arbitrary polyline/path corners cannot be
  replaced by tangent arcs before stroking or filling.
- Next: define radius clamping, open/closed contour behavior, and curve-corner policy, then produce
  a new path without mutating the source.
- Done when: acute, obtuse, short-edge, open, closed, and self-intersecting fixtures have stable
  geometry and preserve winding where defined.
- Related: std.pixel.008, std.pixel.009

---
