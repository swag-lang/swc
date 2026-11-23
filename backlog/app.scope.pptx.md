# Swag Scope PPTX Viewer Backlog

Reading and inspecting PowerPoint presentations in PPTX format.

### app.scope.pptx.001 — PPTX reading omits charts and complex slide geometry

- Evidence: the PPTX reader now fits individual slides at authored aspect ratio, retaining text
  and raster-picture geometry, solid colors, basic theme colors/text sizes, simple rectangles,
  static master objects, inherited placeholder bounds and simple ellipses. Slide titles appear in the shared
  outline and a bounded five-slide preview rail; arrows, Page Up/Down and a theme-aware text mode
  support reading. Relationship-resolved cached horizontal bar charts render up to eight series
  and 64 categories, and direct `tint`/`shade` color transforms are applied to shapes and runs.
  Vertical and other chart types, grouped drawings, custom geometry, connectors, text-style
  inheritance and other color transforms remain absent. Unsupported geometry falls back to a
  labelled simplified layout. The real Apache POI sample and a widescreen deck cover inherited
  title placement, authored colors, pictures and navigation; slide decoding still loads the full deck.
  A dedicated theme-aware notes reader now exposes bounded speaker prose and emphasis through the lens,
  follows slide navigation and omits notes-page thumbnails, footers and counters.
  [PowerPoint Reading and Slide Show views](https://support.microsoft.com/en-us/powerpoint/how-certain-features-behave-in-web-based-powerpoint)
  retain slide navigation and notes.
  [File Viewer Plus 7](https://fileviewerplus.com/support/presentation_files) documents
  presentation viewing, printing and conversion. Its format matrix also lists PPT, PPTM,
  templates and slide-show variants.
- Next: use real decks with nested groups, custom geometry, connectors and column charts to fix
  the largest remaining geometry gaps. Extend inherited text styles and color transforms with
  bounded fixtures, then move slide package decoding behind selection so off-screen slides stay
  unloaded. Keep animation, embedded media and external actions inert; name every omitted construct.
- Done when: a real presentation is recognizable slide by slide at authored aspect ratio, notes
  and navigation remain available, unsupported effects are explicit, and slide 1 appears without
  decoding every slide. The preview rail stays bounded and follows navigation.
- Related: app.scope.archive.001, app.scope.viewers.009
