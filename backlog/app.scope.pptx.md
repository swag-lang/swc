# Swag Scope PPTX Viewer Backlog

Reading and inspecting PowerPoint presentations in PPTX format.

### app.scope.pptx.001 — PPTX reading omits charts and complex slide geometry

- Evidence: the PPTX reader now fits individual slides at authored aspect ratio, retaining text
  and raster-picture geometry, solid colors, basic theme colors/text sizes, simple rectangles,
  static master objects and inherited placeholder bounds. Slide titles appear in the shared
  outline; arrows, Page Up/Down and a theme-aware text mode support reading. Unsupported geometry
  falls back to a labelled simplified layout. The real Apache POI sample and a widescreen deck
  cover inherited title placement, authored colors, pictures and navigation. Charts, complex
  drawings, complete text inheritance and a thumbnail overview remain absent. A dedicated
  theme-aware notes reader now exposes bounded speaker prose and emphasis through the lens,
  follows slide navigation and omits notes-page thumbnails, footers and counters.
  [PowerPoint Reading and Slide Show views](https://support.microsoft.com/en-us/powerpoint/how-certain-features-behave-in-web-based-powerpoint)
  retain slide navigation and notes.
  [File Viewer Plus 7](https://fileviewerplus.com/support/presentation_files) documents
  presentation viewing, printing and conversion. Its format matrix also lists PPT, PPTM,
  templates and slide-show variants.
- Next: use a PowerPoint deck with master placeholders, grouped drawings and charts to fix
  the largest geometry gaps. Extend text inheritance and color transforms with the same
  fixtures, then add a thumbnail overview and decode off-screen slides lazily. Keep animation,
  embedded media and external actions inert and make omitted content explicit.
- Done when: a real presentation is recognizable slide by slide at authored aspect ratio, notes
  and navigation remain available, unsupported effects are explicit, and slide 1 appears without
  decoding every slide.
- Related: app.scope.archive.001, app.scope.viewers.009
