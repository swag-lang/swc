# Swag Scope Text Viewer Backlog

This backlog covers the Swag Scope adapters and application-owned behavior of the basic text,
code, subtitle, table, diff, and log viewers. Markdown and HTML integration lives in
[app.scope.document.md](app.scope.document.md); engine work owned by `std/gui` remains in
[std.gui.html.md](std.gui.html.md), [std.gui.markdown.md](std.gui.markdown.md), or [std.gui.md](std.gui.md).

## Shared text reading

### app.scope.text.001 — Text zoom is not persisted and has no Ctrl+wheel gesture

- Evidence: basic text, code, Markdown, and HTML now expose the same percentage menu and
  Ctrl+plus/minus/reset gestures. The value is per-view only, is not persisted, and Ctrl+wheel is
  not connected to it.
- Complete when: a shared zoom command changes text size in every basic and format-specific text view, is
  persisted, and leaves the streaming window arithmetic correct.

### app.scope.text.002 — Text navigation has no line, column, byte-offset, or percentage jump

- Evidence: basic text and code can reach the file ends and host search matches, but there is no
  Go To command, address readout, or conversion between resident editor positions and whole-file
  byte offsets.
- Next: introduce a streamed text-position map and a Go To surface that accepts line, `line:column`,
  absolute byte offset, and percentage.
- Complete when: jumps work before a full line index exists, report exact versus estimated
  positions, align to an encoding boundary, and keep line/column/offset visible for the caret.

### app.scope.text.003 — Basic text has no line numbers, whitespace view, or newline diagnostics

- Evidence: the basic viewer presents decoded content as an unadorned rich edit. Mixed CRLF/LF/CR,
  tabs, trailing spaces, control characters, BOMs, and missing final newlines are invisible.
- Next: add a virtual line gutter and optional non-printing-character layer without injecting
  decoration into selectable text.
- Complete when: whole-file line numbers remain correct across streamed windows, mixed newline
  kinds and invalid/control bytes are distinguishable, tabs and spaces can be shown, and copy
  returns only source text.

### app.scope.text.004 — Character encoding choice is too narrow and cannot explain decoding damage

- Evidence: the selector offers UTF-8, UTF-16/32 LE/BE, and Windows-1252. It cannot choose an OEM
  code page, ISO-8859 family, Shift-JIS, GB18030, or EBCDIC; replacement characters do not reveal
  their source byte range or why probing chose an encoding.
- Next: separate encoding registry, probe confidence, and decoder diagnostics, then add the most
  common legacy encodings supported by a bounded conversion path.
- Complete when: encoding can be searched and overridden, BOM and statistical evidence are shown,
  invalid sequences identify their bytes, line/offset mapping survives every decoder, and the
  choice persists through app.scope.viewers.003.

### app.scope.text.005 — Streamed text cannot select, copy, or export a range outside its resident window

- Evidence: app.scope.viewers.001 records that select-all means only the resident window. The same limitation
  prevents a reader from naming two whole-file positions and extracting the text between them.
- Next: give streamed text a byte-backed range model and a cancellable decoder-to-clipboard/file
  path with explicit size estimates.
- Complete when: a non-resident range can be selected by endpoints, copied within a documented
  clipboard bound, exported without that bound, and decoded consistently across chunk boundaries.
- Related: app.scope.viewers.001

## Source code

### app.scope.text.006 — Source files have no outline or symbol navigation

- Evidence: `CodeViewer` colors tokens but exposes no functions, types, headings, regions, or
  breadcrumbs. Professional code readers use an outline both to understand a file and to jump
  within it.
- Next: define a lightweight read-only symbol provider, starting with Swag and indentation/marker
  fallbacks, whose results retain whole-file byte ranges.
- Complete when: symbols form a filterable hierarchy, track the visible scope, jump before the
  full file is resident, and malformed syntax yields partial symbols instead of losing the outline.

### app.scope.text.007 — Source code cannot fold regions

- Evidence: the streamed rich edit has no fold ranges, gutter affordance, or folded-height model;
  comments, regions, declarations, and indentation blocks always occupy their full height.
- Next: add fold ranges independent of styling, beginning with marker and indentation providers
  that can be reconciled as streamed content enters and leaves memory.
- Complete when: fold/unfold current, recursive, all, and level commands preserve navigation and
  search reveal; hidden matches can be opened; and folds restore only against the same file version.

### app.scope.text.008 — Source code has no minimap, overview ruler, or durable location markers

- Evidence: search highlights exist only in the resident editor and the scrollbar carries no
  whole-file density, match, diagnostic, or symbol marks.
- Next: build a bounded whole-file overview index from line starts, styles, search batches, and
  symbols, then render it as an optional minimap or ruler.
- Complete when: dragging navigates the whole file, markers remain proportional on huge inputs,
  visible-window position is clear, and disabling the overview removes its indexing cost.

### app.scope.text.009 — Syntax language and highlighting rules cannot be inspected or overridden

- Evidence: `codeLanguage` chooses from file name and extension, and `GenericCodeLexer` applies a
  fixed keyword lexer. A misclassified or extensionless file has no language selector, and the UI
  gives no language name or reason for the choice.
- Next: publish language identity in the command bar and allow a temporary or persisted override,
  including Plain Text.
- Complete when: every supported language is selectable, detection evidence is visible, overrides
  re-highlight the resident window immediately, and opening an unsupported language stays readable.

### app.scope.text.010 — Highlighting has no conformance corpus or semantic limits

- Evidence: tests cover representative keywords and a few source fixtures, but nested comments,
  interpolation, raw strings, preprocessor branches, malformed tokens, and multi-chunk lexical
  state are not specified per language.
- Next: declare the lexer contract as lexical rather than semantic and add a compact adversarial
  corpus for each language family plus chunk-boundary variants.
- Complete when: supported constructs and deliberate omissions are documented, state resumes
  correctly after a streamed seek, and each shipped language family has golden style spans.

## Timed text

### app.scope.text.011 — Subtitle navigation has no current-cue timeline

- Evidence: SubRip and related files become a searchable timestamped transcript. The information
  bar now exposes validated Go To Cue and Go To Time dialogs, and host search reveals exact cues,
  but there is no previous/next cue command, current-cue marker, duration filter, or timeline.
- Next: expose previous/next cue as named keyboard commands, keep a current-cue state shared by
  direct jumps and search, and add a compact time ruler with overlap markers.
- Complete when: cue and time jumps are keyboard accessible, invalid base-60 times are rejected,
  overlapping cues are grouped, the current cue is marked, and search reveal, cue selection, and
  timeline position remain synchronized.

### app.scope.text.012 — Subtitle syntax, styling, and diagnostics disappear in transcript mode

- Evidence: the dedicated viewer shows normalized cue text and times only. Cue identifiers,
  WebVTT settings, ASS styles, positioning, comments, malformed timing, and unsupported tags cannot
  be inspected or traced back to source.
- Next: add Normalized, Styled Preview, and Source modes sharing exact cue/source ranges.
- Complete when: switching modes preserves the cue, parsing warnings point to source text,
  supported styling and placement can be previewed safely, and unsupported constructs remain visible.

### app.scope.text.013 — Subtitle timing cannot be checked against media

- Evidence: the standalone subtitle viewer has no way to associate a video or sound file, overlay
  cues, visualize waveform/frame timing, or apply a temporary delay and frame-rate conversion.
- Next: let the reader attach one local media file without modifying either input and reuse the
  existing video subtitle overlay and media clock.
- Complete when: cues preview over media, delay and FPS conversion are reversible session settings,
  gaps/overlaps/out-of-order cues are flagged, and no transcoding or source rewrite is implied.

### app.scope.text.014 — Subtitle text has no focused interchange commands

- Evidence: generic selection can copy transcript text, but there is no copy-current-cue, copy
  plain dialogue, export normalized transcript, or report of cues omitted because of parser damage.
- Next: add cue-aware copy commands and bounded exports that preserve explicit timing policy.
- Complete when: one cue, selected cues, dialogue-only text, and a normalized transcript can be
  copied or exported, and lossy normalization is summarized before writing.

## Tabular text

### app.scope.text.015 — The table viewer is bounded to 32 MiB

- Intent: the table viewer detects comma, semicolon, tab or pipe separators, understands quoted
  fields and embedded line breaks, keeps its header visible, and virtualizes the GUI rows. It reads
  at most 32 MiB because the parsed source rows are still resident; the streamed basic-text viewer
  remains selectable for a larger file instead of the table exhausting memory.
- Complete when: source rows are themselves streamed through a bounded window and the row count is
  updated as the file is indexed, without weakening quoting across chunk boundaries.

### app.scope.text.016 — Delimiter, quoting, header, and encoding decisions cannot be corrected

- Evidence: table detection picks comma, semicolon, tab, or pipe and treats the first row as
  headers. There is no import surface for a custom separator, quote/escape policy, header toggle,
  comment rows, locale, or text encoding.
- Next: expose detected dialect with a live bounded preview and allow the reader to override each
  decision without editing the source.
- Complete when: custom one-character delimiters, tab, quote/escape modes, header presence,
  comments, newline policy, and encoding can be changed; detection confidence and parse warnings
  are visible; and the chosen dialect persists.

### app.scope.text.017 — Table columns cannot be sorted, filtered, hidden, reordered, or frozen

- Evidence: the virtual list keeps one header visible but presents source row order and every
  column unconditionally. Wide or noisy datasets cannot be reduced to the fields and records under
  investigation.
- Next: add a view index over source rows plus column presentation state, initially one stable sort,
  value/text filters, visibility, width, order, and frozen leading columns.
- Complete when: operations stay bounded through app.scope.text.015, source row numbers remain available,
  multi-column stable sort and composable filters can be cleared, and no operation rewrites the file.

### app.scope.text.018 — Table values have no type inference or professional formatting

- Evidence: every cell is a string. Numbers, dates, times, booleans, nulls, percentages, and units
  cannot align, sort, filter, or format by their meaning, and inference errors are silent.
- Next: sample then incrementally refine a nullable column type with locale-independent parsing and
  an explicit user override.
- Complete when: original text is always inspectable, inferred type/confidence and failures are
  counted, numeric/date sorting is semantic, formats are configurable, and mixed columns degrade
  safely to text.

### app.scope.text.019 — Table selection and clipboard interchange stop at one cell preview

- Evidence: search can reveal a cell and long cells use a bounded preview, but there is no row,
  column, rectangle, discontiguous selection, copy-with-headers, or export-visible-rows command.
- Next: introduce a source-backed cell-range selection model and stream serializers for TSV, CSV,
  JSON Lines, and plain text.
- Complete when: keyboard and pointer ranges work across virtual rows, copied data uses a declared
  bound, export does not, long cells are complete in output, and dialect/quoting is correct.

### app.scope.text.020 — Table exploration has no summaries, grouping, or duplicate analysis

- Evidence: the viewer reports only row and column counts. It cannot show null/error/distinct
  counts, min/max, distributions, top values, duplicate rows, or lightweight groups.
- Next: build cancellable per-column sketches over the row stream, followed by exact calculations
  on demand for one column or filtered subset.
- Complete when: statistics state sampled versus exact scope, memory remains bounded for high
  cardinality, duplicate/group results link back to source rows, and analysis can be cancelled.

### app.scope.text.021 — Table navigation has no stable row identity or direct cell address

- Evidence: the reader can scroll and search but cannot jump to source row, visible row, column,
  or `R:C` cell; sorting and filtering from app.scope.text.017 will make those coordinate systems diverge.
- Next: define source and view coordinates before adding a name/address box and navigation history.
- Complete when: direct jumps identify their coordinate space, headers are searchable, current cell
  and source row remain visible, and back/forward survives sort and filter changes where possible.

## Dedicated developer-text views

### app.scope.text.022 — Diff and patch files read as plain text

- Intent: unified diffs are among the most frequently opened developer files and are the format
  where flat text costs the most.
- Complete when: hunks, added and removed lines and file headers are colored from the active theme,
  and per-file navigation moves between hunks.

### app.scope.text.023 — Log files have no dedicated view

- Intent: a log is the archetypal huge file, which is where the streaming architecture already
  wins — but it opens at the beginning, uncolored, with no way to reach the end that matters.
- Complete when: severity levels and timestamps are recognized and colored, the view can open at the
  tail, and a level filter narrows what is shown without loading the file.
