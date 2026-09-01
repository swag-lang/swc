# Swag Scope Application Backlog

This backlog covers the Swag Scope application shell: document lifecycle, process and window
management, viewer hosting, and persisted application state. Operating-system integration lives
in [platform.portability.md](platform.portability.md). Work
owned by a viewer lives in the corresponding domain:

- [app.scope.viewers.md](app.scope.viewers.md) — shared viewer contracts, coverage, and product scope
- [app.scope.text.md](app.scope.text.md) — basic text, code, subtitle, table, diff, and log viewers
- [app.scope.document.md](app.scope.document.md) — Markdown, HTML, PDF, office-document, and ebook viewers
- [app.scope.binary.md](app.scope.binary.md) — structured binary and container viewer
- [app.scope.hexa.md](app.scope.hexa.md) — hexadecimal viewer
- [app.scope.image.md](app.scope.image.md) — image viewer
- [app.scope.audio.md](app.scope.audio.md) — sound viewer
- [app.scope.video.md](app.scope.video.md) — video viewer
- [app.scope.font.md](app.scope.font.md) — font viewer
- [app.scope.midi.md](app.scope.midi.md) — MIDI viewer

Reusable engine work remains in the backlog of the standard module that owns it. Entries here are
ordered by expected product value, not implementation effort.

## Document lifecycle

### app.scope.001 — One document per window and per process

- Intent: every association launch starts another process with one document. There is no tab, no
  second document in the same window, and no side-by-side comparison of two files.
- Complete when: a running instance is reused, documents open as tabs, and two documents can be
  shown side by side.
- Related: std.gui.029, app.scope.hexa.003 in [app.scope.hexa.md](app.scope.hexa.md)
