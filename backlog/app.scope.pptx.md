# Swag Scope PPTX Viewer Backlog

Reading and inspecting static PowerPoint presentations. This viewer target is based on the reading and slide-show capabilities documented by [PowerPoint for the web](https://support.microsoft.com/en-us/powerpoint/how-certain-features-behave-in-web-based-powerpoint) and the presentation content supported by [LibreOffice Impress](https://help.libreoffice.org/latest/en-US/text/simpress/main0503.html); it does not imply editing parity.

### app.scope.pptx.002 — Render grouped drawings and remaining slide geometry

- Evidence: SwagScope retains authored slide dimensions, static master objects, inherited placeholder bounds, rectangles, rounded rectangles, ellipses, individual shape rotations/flips, one-level unrotated groups with uniform scale, and simple horizontal, vertical, and diagonal solid connectors. Nested or rotated groups, connector arrowheads, custom geometry, SmartArt, and other unsupported graphic frames still use the simplified fallback.
- Next: add nested and rotated group transforms plus connector arrowheads with compact real-world fixtures; preserve the explicit fallback for unsupported constructs.
- Done when: common grouped drawings and connectors retain their authored bounds and appearance, while unsupported geometry keeps readable text and marks the slide simplified.
- Related: app.scope.pptx.008

### app.scope.pptx.004 — Preserve text and theme formatting

- Evidence: paragraphs and runs retain direct bold, italic, underline, strike, alignment, simple bullet glyphs, common automatic Arabic numbering within one text body, direct colors, and basic `tint`/`shade`. Other numbering schemes, cross-shape list continuation, inherited paragraph/run style cascades, theme fonts, text autofit and direction, and gradient or pattern fills are not represented.
- Next: resolve placeholder and theme paragraph/run defaults, then cover additional automatic numbering schemes with real-deck typography fixtures.
- Done when: common text hierarchy, automatic numbering schemes, theme fonts, and inherited run formatting match the source presentation in both slide and reading views; unsupported text effects are named.
- Related: app.scope.pptx.002

### app.scope.pptx.005 — Load large presentations on demand

- Evidence: the viewer creates visible slide previews on demand, but `Presentation.load` decodes every slide before the first slide is shown. Large decks therefore pay the full parsing cost up front.
- Next: separate slide order/metadata discovery from slide decoding and load the selected slide plus preview window on demand.
- Done when: opening slide 1 does not decode later slide XML, navigation loads the selected slide without duplicate decoding, and memory remains bounded by the current slide and preview window.

### app.scope.pptx.006 — Add a full-screen reading mode

- Evidence: SwagScope provides an outline, slide gallery in the outline, previous/next controls, Page Up/Down, Home/End, notes, and text mode. It has no full-screen slide-show mode.
- Next: add a full-screen read-only mode with keyboard navigation, Escape to return, and the current notes/navigation behavior preserved.
- Done when: a reader can start at the selected slide, advance and go back through the deck in full screen, and exit without losing the selected slide.
- Related: app.scope.pptx.005

### app.scope.pptx.008 — Identify omitted and inert presentation content

- Evidence: unsupported geometry currently sets a slide-level simplified flag, which does not tell readers whether a SmartArt object, effect, media object, external link, or other content was omitted. PowerPoint and Impress document transitions, animations, audio/video, and linked content beyond this static viewer's current behavior.
- Next: inventory encountered unsupported OOXML constructs and surface concise per-slide omission details; keep animation, media playback, external actions, and macros inert until each has a deliberate safety and product contract.
- Done when: a reader can identify which visible content was omitted on each simplified slide, active content is never executed implicitly, and the viewer clearly states its static-reading limits.
- Related: app.scope.pptx.002, app.scope.pptx.006

### app.scope.pptx.009 — Preserve table cell formatting and merges

- Evidence: static DrawingML tables retain bounded rows, cell text, basic borders, direct solid cell fills, horizontal `gridSpan` merges, and vertical `rowSpan`/`vMerge` merges through HTML `colspan`/`rowspan`. Authored column proportions, table-style banding, and legacy continuation-cell `hMerge` remain unsupported; unsupported merges preserve text and mark the slide simplified.
- Next: preserve grid column widths and common table-style header/banding roles with visual fixtures, and add coverage for legacy `hMerge` where safely recoverable.
- Done when: ordinary table widths, header/banding colors, and DrawingML merge forms retain their authored structure, while unsupported table effects remain readable and named.
- Related: app.scope.pptx.008

### app.scope.pptx.010 — Render remaining chart families and authored colors

- Evidence: cached bar, column, line, standard area, and positive single-series pie charts render. Direct RGB series colors are preserved for cached bar, column, line, and area series. Scatter, combo, stacked/smoothed chart variants, workbook-backed data, theme-based chart colors, and point-level formatting remain unsupported or simplified.
- Next: add a common cached scatter family and preserve theme-based chart colors with bounded fixtures and visual tests.
- Done when: the next common chart family and its authored colors render with bounded parsing, while unsupported chart forms retain readable values and are reported as simplified.
- Related: app.scope.pptx.008
