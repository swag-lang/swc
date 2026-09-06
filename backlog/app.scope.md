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

### app.scope.001 — One document per window

- Evidence: `src/main.swg` creates one `ViewerWindow`, which owns one active file and viewer.
  Opening another file replaces that document; there is no document-tab host.
- Next: adopt the GUI document-host contract with independent document ownership, close behavior,
  focus and saved reading state. Keep process reuse behind platform.portability.022's messaging
  contract, and side-by-side presentation separate.
- Complete when: several documents can remain open as tabs in one window, and switching or closing
  a tab preserves the other documents' state and outstanding-work ownership.
- Related: std.gui.029, platform.portability.022, app.scope.003

### app.scope.003 — Two documents cannot be shown side by side

- Evidence: `ViewerWindow` has one active viewer surface. The application has no pair of independently
  focused document panes; hexadecimal difference analysis remains a separate viewer capability.
- Next: add a split presentation for two open documents with explicit focus and command routing,
  preserving each viewer's reading state when moving between tabs and split panes.
- Complete when: two documents remain visible and independently usable, and closing or replacing
  either pane leaves the other's state and input intact.
- Related: app.scope.001, app.scope.hexa.003
