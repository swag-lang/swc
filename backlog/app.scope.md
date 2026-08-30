# Swag Scope Application Backlog

This backlog covers the Swag Scope application shell: document lifecycle, process and window
management, viewer hosting, and persisted application state. Operating-system integration lives
in [portability.md](portability.md). Work
owned by a viewer lives in the corresponding domain:

- [scope.viewers.md](scope.viewers.md) — shared viewer contracts, coverage, and product scope
- [scope.text.md](scope.text.md) — basic text, code, subtitle, table, diff, and log viewers
- [scope.document.md](scope.document.md) — Markdown, HTML, PDF, office-document, and ebook viewers
- [scope.binary.md](scope.binary.md) — structured binary and container viewer
- [scope.hexa.md](scope.hexa.md) — hexadecimal viewer
- [scope.image.md](scope.image.md) — image viewer
- [scope.audio.md](scope.audio.md) — sound viewer
- [scope.video.md](scope.video.md) — video viewer
- [scope.font.md](scope.font.md) — font viewer
- [scope.midi.md](scope.midi.md) — MIDI viewer

Reusable engine work remains in the backlog of the standard module that owns it. Entries here are
ordered by expected product value, not implementation effort.




## Document lifecycle

### B-448 — One document per window and per process

- Intent: every association launch starts another process with one document. There is no tab, no
  second document in the same window, and no side-by-side comparison of two files.
- Complete when: a running instance is reused, documents open as tabs, and two documents can be
  shown side by side.
- Related: B-341, B-022 in [scope.hexa.md](scope.hexa.md)

## Window hosting

### B-622 — Swag Scope sizes its viewer layout in physical pixels, so every viewer overflows at non-100% DPI

- Area: apps/swagscope
- Found while: migrating the PDF engine into `std/gui` and verifying the new `PdfView` inside the
  running Swag Scope on a 150% monitor.
- Observation: Swag Scope hands each integrated viewer a content window sized straight from the
  surface's physical pixel size, while gui lays out and paints in logical units times
  `deviceScale`. At 150% the viewer content area measured 1161x730 logical units inside a window
  whose client is only about 978x598 logical, so the viewer — any viewer, this predates the PDF
  rework — is 1.5x wider and taller than the window: a fitted page centres itself in the
  oversized widget and shows up right-shifted and cut. At 100% DPI physical equals logical and
  nothing is visible, which is how it went unnoticed.
- Evidence: an instrumented `PdfView.onPaint` on both monitors of a 150% setup reported
  `position=0,0,1161x730, deviceScale=1.5, fitted zoom=0.867, content centred at x=322` — the
  widget math is exact, the size it was given is not. The sidebar and toolbar paint at their
  layout size times 1.5, matching the screenshots.
- Next: find where Swag Scope computes the content and command areas from the surface size and
  divide by `deviceScale` there; then check the same path in every host that sizes children from a
  `Surface` rectangle, since the surface contract is physical pixels.
- Complete when: every integrated viewer fits the same logical client rectangle at 100%, 125%,
  150%, and 200% DPI, with an HTML-viewer check and one DPI-aware native-window measurement.
