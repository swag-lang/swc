# Swag Scope PPTX Viewer Backlog

Reading and inspecting PowerPoint presentations in PPTX format.

### app.scope.pptx.001 — PPTX lacks slide geometry and presentation reading

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
- Next: add a thumbnail overview, then lazy slide decoding so the first canvas
  can appear before the rest of the deck is projected. Extend shapes, paragraph styles, color
  transforms and font/theme inheritance with producer fixtures. Keep animation, embedded media
  and external actions inert and make omitted content explicit.
- Done when: a real presentation is recognizable slide by slide at authored aspect ratio, notes
  and navigation remain available, unsupported effects are explicit, and slide 1 appears without
  decoding every slide.
- Related: app.scope.archive.001
