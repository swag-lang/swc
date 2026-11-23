# Swag Scope PPTX Viewer Backlog

Reading and inspecting static PowerPoint presentations. This viewer target is based on the reading and slide-show capabilities documented by [PowerPoint for the web](https://support.microsoft.com/en-us/powerpoint/how-certain-features-behave-in-web-based-powerpoint) and the presentation content supported by [LibreOffice Impress](https://help.libreoffice.org/latest/en-US/text/simpress/main0503.html); it does not imply editing parity.

### app.scope.pptx.002 — Render grouped drawings and remaining slide geometry

- Evidence: SwagScope retains authored slide dimensions, static master objects, inherited placeholder bounds, rectangles, rounded rectangles, ellipses, and individual shape rotations/flips. It reports an entire slide as simplified for grouped drawings, connectors, custom geometry, SmartArt, or other unsupported graphic frames.
- Next: support group transforms and common connectors using compact real-world fixtures; preserve the existing explicit fallback for unsupported constructs.
- Done when: common grouped drawings and connectors retain their authored bounds and appearance, while unsupported geometry keeps readable text and marks the slide simplified.
- Related: app.scope.pptx.003, app.scope.pptx.008

### app.scope.pptx.003 — Render common chart families

- Evidence: relationship-resolved cached horizontal bar and vertical column charts render signed values with up to eight series and 64 categories. Line, pie, area, scatter, combo, and workbook-backed chart data are not rendered; unsupported mixed charts mark the slide simplified.
- Next: add cached line and pie charts with deterministic fixtures, bounded parsers, and visual regression coverage.
- Done when: common cached column, line, and pie charts render signed values and labels with bounded parsing, while unsupported chart families keep the slide readable and are reported as simplified.
- Related: app.scope.pptx.002, app.scope.pptx.008

### app.scope.pptx.004 — Preserve text and theme formatting

- Evidence: paragraphs and runs retain direct bold, italic, underline, strike, alignment, simple bullet glyphs, direct colors, and basic `tint`/`shade`. Automatic bullet numbering, inherited paragraph/run style cascades, theme fonts, text autofit and direction, and gradient or pattern fills are not represented.
- Next: resolve placeholder and theme paragraph/run defaults, then add automatic list numbering with real-deck typography fixtures.
- Done when: common text hierarchy, automatic numbering, theme fonts, and inherited run formatting match the source presentation in both slide and reading views; unsupported text effects are named.
- Related: app.scope.pptx.002

### app.scope.pptx.005 — Load large presentations on demand

- Evidence: the viewer creates a bounded five-slide preview rail, but `Presentation.load` decodes every slide before the first slide is shown. Large decks therefore pay the full parsing cost up front.
- Next: separate slide order/metadata discovery from slide decoding and load the selected slide plus preview window on demand.
- Done when: opening slide 1 does not decode later slide XML, navigation loads the selected slide without duplicate decoding, and memory remains bounded by the current slide and preview window.

### app.scope.pptx.006 — Add a full-screen reading mode

- Evidence: SwagScope provides an outline, five-slide preview rail, previous/next controls, Page Up/Down, Home/End, notes, and text mode. It has no full-screen slide-show mode.
- Next: add a full-screen read-only mode with keyboard navigation, Escape to return, and the current notes/navigation behavior preserved.
- Done when: a reader can start at the selected slide, advance and go back through the deck in full screen, and exit without losing the selected slide.
- Related: app.scope.pptx.005

### app.scope.pptx.007 — Define supported presentation package formats

- Evidence: the viewer registers `.pptx` only. PowerPoint for the web documents `.ppt` and `.pps` viewing; other presentation packages such as macro-enabled decks, templates, and slide shows have no declared support contract here.
- Next: publish a format support matrix, then add one safe read-only fixture for each additional OOXML package type chosen for support; never execute embedded macros or external actions.
- Done when: every registered suffix has a passing fixture and a documented decoding contract, while unsupported formats are rejected with a clear format-specific notice.
- Related: app.scope.pptx.008

### app.scope.pptx.008 — Identify omitted and inert presentation content

- Evidence: unsupported geometry currently sets a slide-level simplified flag, which does not tell readers whether a SmartArt object, effect, media object, external link, or other content was omitted. PowerPoint and Impress document transitions, animations, audio/video, and linked content beyond this static viewer's current behavior.
- Next: inventory encountered unsupported OOXML constructs and surface concise per-slide omission details; keep animation, media playback, external actions, and macros inert until each has a deliberate safety and product contract.
- Done when: a reader can identify which visible content was omitted on each simplified slide, active content is never executed implicitly, and the viewer clearly states its static-reading limits.
- Related: app.scope.pptx.002, app.scope.pptx.003, app.scope.pptx.006, app.scope.pptx.007

### app.scope.pptx.009 — Preserve table cell formatting and merges

- Evidence: static DrawingML tables retain bounded rows, cell text, basic borders, and direct solid cell fills. Authored column proportions, table-style banding, and merged cells are not rendered; merged cells mark the slide simplified.
- Next: preserve grid column widths, apply common table-style header/banding roles, and implement merged-cell spans with visual fixtures.
- Done when: ordinary table widths, header/banding colors, and merged cells retain their authored structure, while unsupported table effects remain readable and named.
- Related: app.scope.pptx.008
