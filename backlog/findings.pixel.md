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
