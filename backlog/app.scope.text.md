# Swag Scope Text Viewer Backlog

This backlog covers the Swag Scope adapters and application-owned behavior of the basic text,
code, subtitle, table, diff, and log viewers. Raw source access for an inherently textual format
also belongs here; rendered Markdown and HTML integration lives in
[app.scope.document.md](app.scope.document.md). Engine work owned by `std/gui` remains in
[std.gui.html.md](std.gui.html.md), [std.gui.markdown.md](std.gui.markdown.md), or [std.gui.md](std.gui.md).

The competitive baseline is deliberately read-only. [Visual Studio Code's basic editor](https://code.visualstudio.com/docs/editing/codebasics)
provides encoding choice, folding, file comparison, and direct navigation, while its
[editor surface](https://code.visualstudio.com/docs/editing/userinterface) adds a minimap, sticky
scope, indentation guides, and breadcrumbs. [EmEditor](https://help.emeditor.com/en/features_index.html)
sets the large-file baseline with partial-file opening, markers, filtering, and bounded work on
multi-gigabyte inputs. [klogg](https://github.com/variar/klogg/blob/master/DOCUMENTATION.md) sets the
log-reading baseline with regular-expression result panes, match overviews, reusable highlighters,
marks, and follow mode. Swag Scope should adopt those inspection outcomes without adding editing,
implicit network access, macros, or source mutation.

## Shared text reading

### app.scope.text.025 — Textual formats can hide their raw source

- Evidence: `Basic text` registers a closed list of extensions rather than a raw-source
  capability. A `.md` file therefore offers Markdown, Binary, and Hexadecimal, but not Basic text;
  HTML offers rendered HTML and Code, while CSV, JSON, XML, YAML, TOML, and subtitles expose
  inconsistent source alternatives. The README's claim that Basic text follows a format-specific
  viewer is consequently not true for Markdown or CSV.
- Next: let a format descriptor declare that its bytes are inherently textual and offer Basic text
  after the preferred semantic viewer, beginning with every Markdown selector.
- Complete when: `.md` and `.markdown` offer Markdown, Basic text, Binary, and Hexadecimal in that
  order; every inherently textual built-in has one predictable raw-source choice; unreadable bytes
  fail with an encoding explanation rather than fabricated text; binary documents are never
  admitted merely because a printable prefix passes a probe; and remembered viewer choice keeps
  working per format.
- Related: app.scope.document.002, app.scope.viewers.003

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

### app.scope.text.026 — Whole-file search has no inspectable result set or context projection

- Evidence: shared search supports case, whole-word, and regular-expression matching across the
  whole file, but exposes only one highlighted occurrence and a current/total counter. EmEditor and
  klogg can retain matching lines, surrounding context, and a whole-file match overview, which is
  the difference between finding one error and investigating a large report.
- Next: publish the streamed match index as a virtual result pane with configurable context lines
  and an optional matches-only projection over immutable source ranges.
- Complete when: results show line, byte offset, matched text, and bounded before/after context;
  activating a row reveals the source; the overview represents the whole file; duplicate or
  overlapping matches remain unambiguous; context can be expanded locally; and closing the pane
  releases its index without changing the file.

### app.scope.text.043 — Regular-expression search has no declared resource budget

- Evidence: the host scans regular expressions over asynchronous chunks, but the backlog and
  compatibility matrix do not state a complexity policy, per-chunk deadline, cancellation latency,
  match-count ceiling, zero-length-match rule, or behavior for a pattern whose match crosses chunk
  boundaries. A valid but pathological expression can therefore undermine the bounded-reader claim.
- Next: specify the accepted expression engine and streamed matching contract, then add adversarial
  patterns and boundary-spanning fixtures before exposing result projections more widely.
- Complete when: regex compilation and matching have explicit time, memory, stack, and result
  limits; cancellation meets a measured latency; zero-length and overlapping matches advance
  deterministically; boundary-spanning results are correct or the documented maximum look-behind
  is enforced; and exhaustion is reported separately from no match.
- Related: app.scope.text.026, app.scope.viewers.004, app.scope.viewers.009

### app.scope.text.027 — Plain text has no bookmarks or navigation trail

- Evidence: a reader can jump through search results and to the file ends, but cannot mark a line,
  revisit arbitrary investigation points, or move backward after a distant seek. Binary already
  demonstrates a bounded row-navigation history, and klogg exposes marks plus previous/next-mark
  navigation.
- Next: define byte-backed text locations with an optional label and a bounded back/forward trail.
- Complete when: bookmark current line, previous/next bookmark, back, forward, list, rename, and
  clear are keyboard reachable; locations survive streamed-window eviction; stale locations are
  detected after replacement; and persistence is an explicit part of app.scope.viewers.003.
- Related: app.scope.viewers.003, app.scope.viewers.005

### app.scope.text.028 — Pathological long lines have no bounded rendering contract

- Evidence: the text reader bounds its resident byte window but still hands each decoded chunk to
  one rich-edit document. Minified JSON, generated source, stack traces, and machine logs can put
  hundreds of megabytes in one logical line, defeating ordinary wrap, shaping, gutter, selection,
  and line-index assumptions even when total resident bytes are capped.
- Next: measure shaping and navigation against escalating single-line fixtures, then introduce a
  visual-segment model whose source identity remains one line.
- Complete when: first content, horizontal navigation, wrap toggling, search reveal, selection, and
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
- Complete when: the caret reports code point, UTF spelling, Unicode name/category, byte range, and
  normalization state; directional and zero-width controls receive visible, selectable markers;
  suspicious mixed scripts can be highlighted without claiming malicious intent; and copy can
  choose exact source or an explicitly escaped representation.

### app.scope.text.030 — Text statistics stop at line and word counts

- Evidence: the background pass reports lines and words only. It does not expose decoded scalar
  count, byte count excluding BOM, newline-kind totals, longest line, invalid-sequence count,
  control-character count, or sampled versus exact scope, so it cannot explain why a document
  renders or navigates unexpectedly.
- Next: turn the existing bounded statistics worker into a cancellable text profile shared with
  newline and encoding diagnostics.
- Complete when: every metric names its unit and exact or sampled scope, line-length extremes link
  to source, newline and decode totals reconcile with app.scope.text.003 and .004, progress can be
  cancelled, and profiling does not delay first content.
- Related: app.scope.text.003, app.scope.text.004, app.scope.viewers.004

### app.scope.text.042 — Text layout cannot control tab width, wrap column, or reading ruler

- Evidence: Basic text exposes wrap on/off and zoom only. A tab always inherits the widget default,
  wrapped lines follow the viewport rather than a chosen column, and there is no column ruler,
  horizontal guide, line-spacing choice, or explicit fixed-font identity to explain alignment.
- Next: define presentation-only text layout settings shared with Code, keeping every source
  position independent of visual lines and glyph metrics.
- Complete when: tab width, viewport versus fixed-column wrapping, wrap column, line spacing, font,
  and optional column ruler can be inspected and changed; invalid or mixed tabs remain diagnosable;
  horizontal scrolling is stable with wrap off; settings persist through app.scope.viewers.003;
  and no presentation choice changes copied text or byte/line/column addressing.
- Related: app.scope.text.002, app.scope.text.003, app.scope.text.028

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

### app.scope.text.031 — Source structure has no sticky scope, indentation guides, or delimiter matching

- Evidence: lexical color is the only structural cue inside the code surface. VS Code keeps the
  current nested scope visible while scrolling, draws indentation guides, and pairs brackets;
  those aids remain useful in a read-only single-file reader and do not require project semantics.
- Next: derive indentation, delimiter pairs, and sticky headings from the same bounded lexical and
  outline ranges planned by app.scope.text.006 and .010.
- Complete when: the current scope path remains visible and navigable, indentation guides survive
  tabs and mixed widths honestly, matching and unmatched delimiters are distinguishable, each cue
  can be disabled independently, and streamed seeks reconstruct enough preceding state without
  rescanning the whole file synchronously.
- Related: app.scope.text.006, app.scope.text.007, app.scope.text.010

### app.scope.text.032 — Paths, URLs, includes, and source references are inert text

- Evidence: the code viewer cannot identify a local include/import, file-and-line diagnostic,
  relative path, URL, issue number, or symbol reference as an inspectable target. Copying and
  manually reopening a target loses provenance, while activating arbitrary text without a policy
  would weaken Swag Scope's offline and untrusted-input guarantees.
- Next: define non-executing link providers that first expose target spelling, resolution, source
  range, and trust state, then allow explicit navigation only through host-owned file opening.
- Complete when: supported references are underlined only when resolution is known, hover or a
  panel shows the exact target before activation, relative paths cannot escape the approved local
  context silently, remote URLs are never fetched, missing and ambiguous targets are explained,
  and back navigation returns to the originating byte range.
- Related: app.scope.document.003, app.scope.viewers.011

### app.scope.text.044 — One source view cannot pin two distant regions

- Evidence: understanding a declaration and its use, two related log events, or the beginning and
  end of a generated file requires repeatedly abandoning one location. A second synchronized view
  of the same immutable byte source would add comparison context without introducing document tabs
  or a second file lifecycle.
- Next: let Text and Code split their content area horizontally or vertically into two bounded
  resident windows sharing one file identity, search index, settings, and bookmark model.
- Complete when: either pane can navigate independently, the active pane is unambiguous, search and
  bookmarks reveal in the intended pane, split orientation and ratio are keyboard accessible,
  resident memory stays within a declared combined budget, and closing the split returns to the
  surviving logical position without reopening the file.
- Related: app.scope.001, app.scope.text.027, app.scope.viewers.003

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

### app.scope.text.041 — Fixed-width and whitespace-aligned records have no table view

- Evidence: tables require comma, semicolon, tab, or pipe delimiters. Fixed-width exports, aligned
  command output, and space-delimited scientific data therefore remain plain text even when a
  stable column layout is visible, and naïve whitespace splitting would corrupt empty or padded
  fields.
- Next: add an explicit fixed-width mode with ruler-picked boundaries and a sampled whitespace
  detector that never becomes the default without high confidence.
- Complete when: boundaries can be added, moved, removed, and named over a bounded preview; source
  columns retain exact byte ranges; proportional fonts cannot disguise alignment; ragged and short
  records publish diagnostics; and the virtual table features operate without rewriting input.
- Related: app.scope.text.015, app.scope.text.016

## Dedicated developer-text views

### app.scope.text.022 — Diff and patch files read as plain text

- Evidence: unified diffs are among the most frequently opened developer files and are the format
  where flat text costs the most. The current Text view cannot distinguish file headers, metadata,
  hunks, additions, removals, context, no-newline markers, binary notices, renames, modes, or
  malformed ranges. VS Code's diff viewer adds inline/side-by-side layouts, collapsed unchanged
  regions, previous/next-change navigation, and an accessible unified representation.
- Next: parse unified and Git patch syntax into immutable file/hunk/line ranges, beginning with a
  themed unified view and a file/hunk outline before adding a synchronized side-by-side projection.
- Complete when: file and hunk navigation, inline and side-by-side layouts, intraline differences,
  whitespace visibility, collapsed context, exact source copying, malformed-hunk diagnostics, and
  keyboard/screen-reader change navigation work without offering stage, revert, or patch apply.

### app.scope.text.033 — Two local text files cannot be compared

- Evidence: Swag Scope can read a patch that another tool produced, but it cannot compare the open
  text with another local file or clipboard snapshot. VS Code exposes file-to-file and
  file-to-clipboard comparison independently of its source-control write operations.
- Next: reuse the immutable diff presentation from app.scope.text.022 with a cancellable,
  memory-budgeted line matcher and explicit left/right source identities.
- Complete when: the reader can select a second local text file or clipboard snapshot, choose
  line-ending and whitespace comparison policy, navigate exact and moved changes, copy from either
  side, and cancel or degrade a huge comparison without modifying either source.
- Related: app.scope.text.022, app.scope.viewers.004

### app.scope.text.023 — Log files have no dedicated view

- Intent: a log is the archetypal huge file, which is where the streaming architecture already
  wins — but it opens at the beginning, uncolored, with no way to reach the end that matters.
- Complete when: common severity and timestamp spellings are recognized with confidence, the
  reader can start at the tail, entries rather than wrapped screen lines are navigable, multiline
  stack traces remain attached to their event, and uncertain parsing falls back to exact text.

### app.scope.text.034 — Live logs cannot follow append, truncation, or rotation

- Evidence: opening a log snapshots its current size. klogg's follow mode keeps the viewport at the
  tail, while real services can append, truncate in place, atomically replace, or rotate and
  recreate a path; treating those events alike either loses records or joins unrelated files.
- Next: specialize the host replacement contract with a log cursor carrying file identity, byte
  offset, decoder state, and whether the reader has scrolled away from the tail.
- Complete when: append resumes on an encoding boundary, manual scrolling pauses auto-follow,
  truncation and replacement are labelled, rotated predecessors can remain available by explicit
  policy, duplicate/omitted byte ranges are reported, and an idle or hot log stays within fixed CPU
  and memory budgets.
- Related: app.scope.viewers.005

### app.scope.text.035 — Logs have no reusable queries, highlighters, or context filters

- Evidence: the shared query can highlight one expression, but an investigation commonly needs
  several named patterns, include/exclude logic, per-pattern colors, and context around each match.
  klogg supports logical regular-expression filters, quick highlighters, match overviews, and
  marks; EmEditor likewise combines filters, markers, and extraction over huge files.
- Next: layer an immutable event projection over the streamed log index with named query clauses,
  highlight rules, exclusion, and before/after context.
- Complete when: literal and regular-expression clauses compose with AND, OR, and NOT; colors remain
  legible in every theme; filtered events retain source offsets and multiline boundaries; counts
  distinguish scanned versus pending input; query sets can be saved without file content; and
  disabling the projection restores source order immediately.
- Related: app.scope.text.026, app.scope.text.027

### app.scope.text.036 — Structured logs collapse into undifferentiated lines

- Evidence: JSON Lines, logfmt, key-value prefixes, and common application envelopes carry level,
  timestamp, logger, thread, request, trace, and message fields, but the reader cannot expose,
  select, filter, or correlate them. For JSON Lines, app.scope.text.024 owns the general data tree;
  the log surface owns event-oriented presentation and field conventions.
- Next: define a bounded record/field adapter with JSON Lines first and logfmt second, retaining the
  exact raw event beside normalized fields.
- Complete when: detected fields and parse confidence are visible, columns can be selected and
  filtered, nested values remain inspectable, duplicate/malformed fields link to their byte range,
  multiline messages stay intact, and switching back to raw text preserves the event.
- Related: app.scope.text.024

### app.scope.text.037 — Events from several logs cannot share one timeline

- Evidence: failures distributed across client, server, build, and worker logs must be correlated
  manually. File timestamps and embedded timestamps may use different zones, precisions, clock
  skews, or no date at all, so a simple lexical merge would present a false chronology.
- Next: allow an explicit set of local log files to feed one virtual timeline with per-source
  color, parser, timezone, and reversible clock-offset settings.
- Complete when: source identity is always visible, timestamp assumptions and unplaced events are
  separated from ordered facts, equal timestamps have deterministic order, filters span sources,
  following remains bounded, and no source file is opened or discovered implicitly.

### app.scope.text.038 — XML has no namespace-aware structural reader

- Evidence: XML, project files, manifests, SVG source, and XML logs open as colored code. Elements,
  attributes, namespaces, text nodes, comments, CDATA, processing instructions, and entity damage
  cannot be explored as a tree or addressed by a stable path.
- Next: build a bounded token/range index and synchronized source/tree view with namespace-aware
  paths, without resolving external entities or fetching schemas.
- Complete when: every node retains its exact source range and qualified name, tree and source
  selection synchronize, namespaces and entity policy are inspectable, XPath-like navigation is
  local and bounded, malformed documents publish safe partial structure, and external resource
  access remains disabled.

### app.scope.text.039 — YAML and TOML have no typed configuration reader

- Evidence: YAML and TOML open as colored code. YAML mappings, sequences, anchors, aliases, tags,
  block scalars, multi-document streams, and duplicate keys are not exposed; TOML tables, arrays of
  tables, dotted keys, dates, integers, and spelling diagnostics likewise remain flat text.
- Next: define format-specific parsers behind one synchronized path/tree/source contract, shipping
  TOML before the substantially larger and riskier YAML surface.
- Complete when: nodes retain exact spelling and source ranges, paths are searchable and copyable,
  duplicate/conflicting keys and type damage are diagnosed, YAML alias expansion is cycle- and
  budget-safe, schemas are never fetched implicitly, and huge collections remain virtualized.

### app.scope.text.040 — INI, properties, and environment files lack a key/value inspection mode

- Evidence: `.ini`, `.cfg`, `.conf`, `.properties`, and `.env` files are colored as generic code or
  shown as text even though sections, keys, repeated assignments, comments, continuations, quoted
  values, and interpolation spellings carry the useful structure. Secret-looking values can also
  be copied or exposed during a presentation with no masking aid.
- Next: add a conservative key/value reader whose dialect is declared or detected and whose values
  remain exact source, with presentation-only masking disabled by default.
- Complete when: sections and keys form a filterable outline, duplicates and malformed records link
  to source, dialect/encoding decisions are visible, masking never changes copy without an explicit
  choice, interpolation is displayed but never evaluated, and no environment variable or external
  file is read to resolve a value.

### app.scope.text.024 — JSON and JSON Lines have no semantic reader

- Evidence: `.json` opens in the Code viewer and `.jsonl` has no registered semantic surface, so
  objects and arrays cannot be explored as a tree, properties cannot be addressed by JSON Pointer,
  duplicate keys and malformed ranges are not summarized, and schema-derived meaning is absent.
  Visual Studio Code provides property navigation, structural folding, validation, and schema
  explanations; Swag Scope can add the read-only parts without inheriting editing or implicit
  network access.
- Next: build a bounded JSON token/range index and a synchronized virtual tree/source view, starting
  with strict JSON and independently streamed JSON Lines before adding optional local schemas.
- Complete when: tree nodes retain exact source byte ranges and original number/string spelling;
  filter and JSON Pointer jump in both directions; malformed input publishes every safe partial
  result plus precise damage; huge arrays and JSON Lines remain paged; search covers keys and values;
  and schemas are local or explicitly supplied rather than fetched from the network.
- Related: app.scope.text.004, app.scope.viewers.004, app.scope.viewers.006
