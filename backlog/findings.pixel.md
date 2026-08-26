# Findings — Pixel

`std/pixel`, including images, text, and the CPU/OpenGL painters. Intent for the same module is
[todo.pixel.md](todo.pixel.md).

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

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
