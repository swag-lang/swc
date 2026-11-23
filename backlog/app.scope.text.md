# Swag Scope Text Viewer Backlog

This backlog covers the plain text viewer and the source reading behavior it shares with
[Code](app.scope.code.md). The surface supports read-only navigation, inspection, and
bounded large-file work. Shared viewer search lives in
[app.scope.viewers.md](app.scope.viewers.md). Rendered document integration lives in the
[Markdown viewer](app.scope.markdown.md) and [HTML viewer](app.scope.html.md) backlogs.
Engine work lives in [std.gui.markdown.md](std.gui.markdown.md), [std.gui.html.md](std.gui.html.md),
and [std.gui.md](std.gui.md).

### app.scope.text.027 — Plain text has no bookmarks or navigation trail

- Evidence: a reader can jump through search results and to the file ends, but cannot mark a line,
  revisit arbitrary investigation points, or move backward after a distant seek. Binary already
  demonstrates a bounded row-navigation history.
- Next: define byte-backed text locations with an optional label and a bounded back/forward trail.
- Done when: bookmark current line, previous/next bookmark, back, forward, list, rename, and
  clear are keyboard reachable; locations survive streamed-window eviction; stale locations are
  detected after replacement; and persistence is an explicit part of app.scope.viewers.003.
- Related: app.scope.viewers.003, app.scope.viewers.005

### app.scope.text.042 — Text layout cannot control tab width, wrap column, or reading ruler

- Evidence: Basic text exposes wrap on/off, zoom and the tab stops. Basic text and Code place a tab
  stop every 2, 4 or 8 spaces, chosen in the lens when a query is typed and, for basic text, in its
  options; the choice follows the reader from file to file within a session but is not saved and
  is not read from the file or an `.editorconfig`. Wrapped lines follow the viewport rather than a
  chosen column, and there is no column ruler,
  horizontal guide, line-spacing choice, or explicit fixed-font identity to explain alignment.
- Next: define presentation-only text layout settings shared with Code, keeping every source
  position independent of visual lines and glyph metrics.
- Done when: tab width, viewport versus fixed-column wrapping, wrap column, line spacing, font,
  and optional column ruler can be inspected and changed; invalid or mixed tabs remain diagnosable;
  horizontal scrolling is stable with wrap off; settings persist through app.scope.viewers.003;
  and no presentation choice changes copied text or byte/line/column addressing.
- Related: app.scope.text.002, app.scope.text.003, app.scope.text.028

### app.scope.text.044 — One source view cannot pin two distant regions

- Evidence: understanding a declaration and its use, two related log events, or the beginning and
  end of a generated file requires repeatedly abandoning one location. A second synchronized view
  of the same immutable byte source would add comparison context without introducing document tabs
  or a second file lifecycle.
- Next: let Text and Code split their content area horizontally or vertically into two bounded
  resident windows sharing one file identity, search index, settings, and bookmark model.
- Done when: either pane can navigate independently, the active pane is unambiguous, search and
  bookmarks reveal in the intended pane, split orientation and ratio are keyboard accessible,
  resident memory stays within a declared combined budget, and closing the split returns to the
  surviving logical position without reopening the file.
- Related: app.scope.001, app.scope.text.027, app.scope.viewers.003

### app.scope.text.028 — Pathological long lines have no bounded rendering contract

- Evidence: the text reader bounds its resident byte window but still hands each decoded chunk to
  one rich-edit document. Minified JSON, generated source, stack traces, and machine logs can put
  hundreds of megabytes in one logical line, defeating ordinary wrap, shaping, gutter, selection,
  and line-index assumptions even when total resident bytes are capped.
- Next: measure shaping and navigation against escalating single-line fixtures, then introduce a
  visual-segment model whose source identity remains one line.
- Done when: first content, horizontal navigation, wrap toggling, search reveal, selection, and
  copy remain responsive for a line larger than the resident window; elision is explicit and
  reversible; and no line-number or byte-offset result is invented at a visual boundary.

### app.scope.text.029 — Unicode controls and confusable text cannot be inspected safely

- Evidence: app.scope.text.003 proposes generic control-character visibility, but source and logs
  can also contain bidi overrides, isolates, zero-width characters, non-breaking spaces, mixed
  normalization forms, homoglyphs, and invalid scalar sequences whose visual order differs from
  their byte order. A read-only security viewer must make those facts inspectable without changing
  the spelling it reports.
- Next: add an opt-in Unicode inspection layer and a caret inspector backed by exact source bytes
  and scalar boundaries.
- Done when: the caret reports code point, UTF spelling, Unicode name/category, byte range, and
  normalization state; directional and zero-width controls receive visible, selectable markers;
  suspicious mixed scripts can be highlighted without claiming malicious intent; and copy can
  choose exact source or an explicitly escaped representation.

### app.scope.text.030 — Text statistics stop at line and word counts

- Evidence: the background pass now reports source bytes, exact versus unknown extent, and the
  longest line's number alongside the existing counts. Tests cover chunk boundaries, a trailing
  CRLF, the empty file, source byte accounting including a BOM, and following the longest-line
  link back to its source; destinations beyond the exact scan limit are marked as estimates from
  bounded samples. Sampled profiling, user-visible progress cancellation, and reconciliation with
  app.scope.text.003 and app.scope.text.004 remain open.
- Next: expose bounded sampled profiling with progress that can be cancelled, then reconcile its
  newline and decode totals with app.scope.text.003 and app.scope.text.004.
- Done when: every metric names its unit and exact or sampled scope, line-length extremes link
  to source, newline and decode totals reconcile with app.scope.text.003 and app.scope.text.004,
  progress can be cancelled, and profiling does not delay first content.
- Related: app.scope.text.003, app.scope.text.004, app.scope.viewers.004

### app.scope.text.003 — Basic text has no newline or control-character diagnostics

- Evidence: basic text and code can mark every space with a dot and every tabulation with a line
  to its stop (`RichEditFlags.DrawBlanks`), without moving the text. The information sheet names
  the line ends, each convention with its count when they are mixed, and says when the last line
  of a text broken into lines has no break after it. Line ends are not marked in the text itself,
  and control characters and a BOM are still invisible.
- Next: extend the blank marks with line-end and control-character marks drawn over the text's
  own advance, without injecting decoration into selectable text.
- Done when: mixed newline kinds and invalid/control bytes are distinguishable and copy returns
  only source text.

### app.scope.text.004 — Character encoding choice is too narrow and cannot explain decoding damage

- Evidence: the selector offers UTF-8, UTF-16/32 LE/BE, and Windows-1252. It cannot choose an OEM
  code page, ISO-8859 family, Shift-JIS, GB18030, or EBCDIC; replacement characters do not reveal
  their source byte range or why probing chose an encoding.
- Next: separate encoding registry, probe confidence, and decoder diagnostics, then add the most
  common legacy encodings supported by a bounded conversion path.
- Done when: encoding can be searched and overridden, BOM and statistical evidence are shown,
  invalid sequences identify their bytes, line/offset mapping survives every decoder, and the
  choice persists through app.scope.viewers.003.

### app.scope.text.005 — Streamed text cannot select, copy, or export a range outside its resident window

- Evidence: app.scope.viewers.001 records that select-all means only the resident window. The same limitation
  prevents a reader from naming two whole-file positions and extracting the text between them.
  [File Viewer Plus 7](https://fileviewerplus.com/support/file_inspection) documents searchable
  raw text inspection on large files. Compare navigation and selection on the same inputs.
- Next: use the encoding-aware address contract in app.scope.text.002 to select a range across
  resident windows, then stream it to the clipboard or a new file with a size estimate.
- Done when: a non-resident range can be selected by endpoints, copied within a documented
  clipboard bound, exported without that bound, and decoded consistently across chunk boundaries.
- Related: app.scope.text.002, app.scope.viewers.001
