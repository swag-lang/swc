# sFileScope Application Backlog

This backlog covers the sFileScope application shell: document lifecycle, process and window
management, viewer hosting, persisted application state, and operating-system integration. Work
owned by a viewer lives in the corresponding domain:

- [filescope.viewers.md](filescope.viewers.md) — shared viewer contracts, coverage, and product scope
- [filescope.text.md](filescope.text.md) — basic text, code, subtitle, table, diff, and log viewers
- [filescope.document.md](filescope.document.md) — Markdown, HTML, PDF, office-document, and ebook viewers
- [filescope.binary.md](filescope.binary.md) — structured binary and container viewer
- [filescope.hexa.md](filescope.hexa.md) — hexadecimal viewer
- [filescope.image.md](filescope.image.md) — image viewer
- [filescope.audio.md](filescope.audio.md) — sound viewer
- [filescope.video.md](filescope.video.md) — video viewer
- [filescope.font.md](filescope.font.md) — font viewer
- [filescope.midi.md](filescope.midi.md) — MIDI viewer

Reusable engine work remains in the backlog of the standard module that owns it. Entries here are
ordered by expected product value, not implementation effort.

## System integration

### T-389 — Nothing appears in the Explorer preview pane

- Intent: the shipped viewers are reachable from where a file is selected. This is the whole reason
  QuickLook won its category: select, look, move on, without launching an application.
- Complete when: a registered preview handler renders the same views inside Explorer's preview
  pane, and `--register-file-types` installs it.
- Note: the handler hosts a view in a process it does not own, so the viewer request/result contract
  has to be usable without the application window. That constraint is worth checking before committing.
- Related: T-396, T-418

### T-393 — The file being viewed cannot be opened with its default application

- Intent: after looking at a file, the next action is always outside the viewer. Showing it in the
  file explorer, handing it to the system application chooser, and copying either its full path or
  its file name now answer from the context menu of the status bar and of both panel lists. What is
  still missing is opening it with its *default* application.
- Complete when: open-with-default joins that menu, and the actions a reader uses most are
  reachable from the action bar rather than only from a right click.

### T-396 — Explorer shows no thumbnail for a viewable file

- Intent: the image, SVG, and Markdown views can produce a representative bitmap; Explorer asks for
  one and gets nothing.
- Complete when: a registered thumbnail provider renders a bounded preview for the formats that can
  produce one, with a size and timeout budget that never blocks a folder listing.
- Related: T-389

### T-418 — File-type registration is Windows-only

- Intent: `Env.registerApplication`, `Env.associateFileExtension`, and the shell integration entries
  above are the whole platform boundary; the viewers, streaming, and structure readers are portable.
- Complete when: desktop registration goes through whatever portable contract T-288 settles on.
- Related: T-266, T-288

## Document lifecycle

### T-397 — One document per window and per process

- Intent: every association launch starts another process with one document. There is no tab, no
  second document in the same window, and no side-by-side comparison of two files.
- Complete when: a running instance is reused, documents open as tabs, and two documents can be
  shown side by side.
- Related: T-233, B-022 in [filescope.hexa.md](filescope.hexa.md)

## Window hosting

### F-156 — sFileScope sizes its viewer layout in physical pixels, so every viewer overflows at non-100% DPI

- Area: apps/sFileScope
- Found while: migrating the PDF engine into `std/gui` and verifying the new `PdfView` inside the
  running sFileScope on a 150% monitor.
- Observation: sFileScope hands each integrated viewer a content window sized straight from the
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
- Next: find where sFileScope computes the content and command areas from the surface size and
  divide by `deviceScale` there; then check the same path in every host that sizes children from a
  `Surface` rectangle, since the surface contract is physical pixels.
- Complete when: every integrated viewer fits the same logical client rectangle at 100%, 125%,
  150%, and 200% DPI, with an HTML-viewer check and one DPI-aware native-window measurement.
