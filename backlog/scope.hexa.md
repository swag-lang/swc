# Swag Scope Hexadecimal Viewer Backlog

This backlog covers the read-only hexadecimal viewer under
`bin/apps/modules/swagscope/src/viewers/hex`. It is measured against HxD, ImHex, 010 Editor, and
Hex Fiend while preserving Swag Scope's differentiators: bounded streaming, instant opening,
offline operation, and no path that modifies the file. Shared window and document lifecycle work
stays in [scope.md](scope.md); cross-viewer contracts stay in
[scope.viewers.md](scope.viewers.md).

The current foundation already has a 256 KiB resident window aligned to 64 KiB, 64-bit offsets,
proportional whole-file scrolling, mouse and keyboard selection, a named 1 MiB clipboard bound,
absolute, named, percentage, decimal, and caret-relative jumps, fitted or fixed row widths, and
8/16/32/64-bit signed, unsigned, hexadecimal, binary, octal, and floating-point readings in either
byte order. Streamed search
accepts hexadecimal byte/nibble wildcards, exact UTF-8, and the active scalar, marks all visible
occurrences, and the information band inspects common scalar readings at the exact caret. The entries below
are what separate that capable grid from a professional binary-analysis viewer.

## Tier A — Core forensic reading

### B-020 — The live data inspector lacks domain readings and copy

- Evidence: the information band now follows `HexGridView.sigCaretChanged` and simultaneously
  spells the exact caret bytes as signed, unsigned, hexadecimal, binary, octal, `f32`/`f64`, and
  printable readings at 8/16/32/64-bit widths in the active byte order, plus boolean at byte width.
  It does not yet expose `f16`, GUID, timestamp, IP, color, BCD, or varint readings, and values
  cannot be copied independently.
- Next: add `f16` and the remaining domain readings, then one copy action per value without changing
  grid grouping.
- Complete when: the inspector simultaneously reports selection start/end/length and the caret as
  signed and unsigned 8/16/32/64-bit integers, hexadecimal, binary, octal, `f16`/`f32`/`f64`,
  boolean, character, GUID, common timestamps, IP addresses, colors, BCD, and varints where enough
  bytes remain; every value can be copied, invalid readings are explicit, and endian is selectable.

### B-021 — Structured fields and hexadecimal bytes do not identify each other

- Evidence: the `Binary` and `Hexadecimal` viewers open the same file as independent cached views.
  A binary report row can reveal a host search offset, but selecting a row does not select its bytes,
  and a hexadecimal caret cannot locate the structure that owns it.
- Next: define a shared byte-range selection contract and connect the two existing viewers before
  adding format-specific overlays.
- Complete when: selecting a structured field reveals and marks its byte range in hexadecimal,
  placing the hexadecimal caret selects the narrowest owning field, nested fields remain
  distinguishable, and PE/ELF/Mach-O views can name file offset plus relevant RVA/VA addresses.
- Related: B-038

### B-022 — The hexadecimal viewer cannot compare files or regions

- Evidence: Swag Scope has no byte-difference model, synchronized paired grids, result list, or
  difference navigation. Application work B-448 is the prerequisite for hosting two documents,
  not the comparison itself.
- Next: design a bounded comparison result stream for two file ranges, then present its first
  differing block in synchronized read-only grids.
- Complete when: two files or two regions of one file can be compared, insertions and deletions are
  aligned rather than shifting every later byte, differing blocks are listed and colored, scrolling
  can synchronize, and previous/next difference remains bounded on multi-gigabyte inputs.
- Related: B-448

### B-023 — Hexadecimal navigation has no landmarks or history

- Evidence: navigation is limited to scrolling, Home/End, host search, and a Go To dialog accepting
  hexadecimal, decimal, percentage, `caret`, `filesize`, and caret-relative positions. There are no
  named ranges, return stack, or list of visited offsets.
- Next: add an in-memory navigation history around every search reveal, Go To, structure jump, and
  bookmark activation, followed by named range bookmarks.
- Complete when: back/forward returns through visited offsets, bookmarks carry an offset or range,
  label, color, and note, previous/next bookmark is available, and bookmarks can be listed,
  exported, and restored only when file identity still matches.

### B-024 — The text lane is ASCII-only

- Evidence: `isHexPrintable` accepts only bytes `0x20..0x7E`; every other byte becomes a dot. The
  lane cannot decode UTF-8, UTF-16/32, Windows/OEM pages, or EBCDIC, and selection has no way to
  associate a multi-byte character with its source bytes.
- Next: introduce a text-lane decoder contract that consumes a bounded row window and maps every
  rendered character back to an exact byte range.
- Complete when: ASCII, Windows-1252, OEM, UTF-8, UTF-16/32 LE/BE, and EBCDIC can be selected;
  invalid sequences and control characters are visible; selection, copy, and search use the same
  encoding; and multi-byte characters highlight all contributing bytes.

### B-025 — Whole-file search cannot yield early, cancel visibly, or bound its matches

- Evidence: host search appends every occurrence to `ViewerWindow.searchMatches`, enables
  navigation only after EOF, and exposes no progress or cancellation action. A file filled with a
  frequent byte sequence can make result memory proportional to file size even though display is
  bounded.
- Next: extend the search contract with incremental batches, cancellation, progress, and a paged or
  capped result index while preserving F3/Shift+F3 wrapping.
- Complete when: the first match is navigable while scanning continues, progress names processed
  bytes, cancellation is immediate, result storage stays bounded on a repetitive multi-gigabyte
  file, and forward/backward/all plus file/selection/range scopes behave consistently.

### B-026 — Scrolling can perform synchronous file I/O during paint

- Evidence: `HexGridView.onPaint` calls `HexDocument.ensure`; crossing a resident-window boundary
  can seek and read 256 KiB on the GUI thread. Local SSD tests hide the stall, while slow disks,
  removable media, and network shares can block input and painting.
- Next: add cancellable background prefetch for the visible window and its immediate neighbors,
  with a stable placeholder while a requested range is pending.
- Complete when: painting never waits for file I/O, sequential scrolling normally hits prefetched
  data, distant jumps retire obsolete reads, progress/error presentation is shared with the host,
  and resident memory remains explicitly bounded.

### B-027 — External file changes can make offsets and search results stale

- Evidence: `HexDocument` records size at open, display and search use separate streams, and a
  later short read permanently fails the document. Growth, truncation, replacement, and writes by
  another process are not detected as file-version changes.
- Next: define a read-only file identity/version snapshot and poll or observe it at bounded points
  around display, copy, and search.
- Complete when: external change is detected, stale matches and interpretations are invalidated,
  reload can preserve a still-valid offset, truncation never presents old bytes as current, and the
  user can distinguish retryable change from a genuine read failure.
- Related: B-045

## Tier B — Navigation, presentation, and interchange

### B-028 — Navigation address expressions remain partial

- Evidence: the information band now reports the caret in hexadecimal and decimal, selection
  bounds and length, the active value, and whole-file percentage. Go To accepts bare and `0x`
  hexadecimal, `0d` decimal, percentages, named `caret` and `filesize`, and signed caret-relative
  deltas with explicit invalid and out-of-range handling.
- Next: extend the side-effect-free parser with arithmetic, alignment, a configurable base address,
  and a named bookmark origin.
- Complete when: caret, selection start/end/length, active value, and file percentage are visible in
  hexadecimal and decimal; Go To accepts named `caret` and `filesize`, arithmetic, alignment,
  percentage, decimal/hex input, configurable base address, and a named bookmark origin; invalid
  and out-of-range expressions remain explicit.

### B-029 — Row layout and reading presentation are only partly configurable

- Evidence: row width is auto or one of 8/16/32/64, byte grouping is fixed at eight in raw-byte
  mode, and grouping and scalar interpretation are coupled. Endian is now an explicit Little/Big
  choice, and Ctrl+wheel or Ctrl+plus/minus zooms the fixed-width font with Ctrl+0 reset.
- Next: separate row width, visual grouping, scalar interpretation, byte order, and font scale into
  persistent presentation choices.
- Complete when: an arbitrary safe bytes-per-row value, 1/2/4/8/16-byte visual groups, sector or
  structure separators, explicit Little/Big endian choice, address radix, control-character style,
  and Ctrl+wheel/Ctrl+plus/minus font scaling all remain readable at the minimum window size.

### B-030 — Copy is capped text, not bounded binary interchange

- Evidence: copy materializes at most the first 1 MiB and emits spaced hex, printable ASCII with
  dots, or the visible dump. There is no raw-byte clipboard form, streamed save-selection path,
  source literal, encoded export, or direct copy of offset, length, and inspected value.
- Next: split small clipboard representations from a streamed selection-export operation.
- Complete when: the viewer can copy offset, range length, inspected value, raw bytes where the
  platform clipboard supports them, C/C++/Swag arrays, escaped strings, Base64, Intel HEX, and
  Motorola S-record text; a selection of any size can be exported to a file without becoming
  resident; and every bounded clipboard command names its exact limit before execution.

### B-033 — A proportional scrollbar gives no whole-file overview

- Evidence: the fixed-span scrollbar keeps every row reachable but shows no distribution of search
  matches, selections, bookmarks, differences, structures, or high-entropy regions. Search now
  marks every occurrence that lies in the visible grid, but there is no whole-file minimap.
- Next: define a downsampled, asynchronously produced overview model whose bins reference byte
  ranges rather than pixels.
- Complete when: a compact minimap marks current viewport, selection, search results, bookmarks,
  comparison blocks, structured ranges, and optional entropy without loading the file or obscuring
  ordinary scrollbar interaction.
- Related: B-022, B-023, B-032

### B-034 — Hexadecimal state is not restored

- Evidence: application serialization persists window, search, recent-file, and viewer-choice
  state, but not hexadecimal width, representation, endian, row layout, encoding, font size,
  caret, selection, scroll position, panels, or bookmarks.
- Next: separate global hexadecimal preferences from per-file session state and give the latter a
  file-identity guard.
- Complete when: stable presentation preferences survive application restarts, reopening the same
  file restores its last useful position and panels, changed files do not inherit unsafe offsets or
  annotations, and state remains bounded across recent files.
- Related: B-023, B-024, B-029, B-043

### B-035 — The custom-painted grid exposes no accessibility semantics

- Evidence: bytes, characters, caret, selection, and column headers are painted directly by one
  `Wnd`; no accessible grid, cell, value, or selection model is published.
- Next: determine the smallest `std/gui` accessibility contract a virtual binary grid needs and
  expose a bounded logical row around the caret through it.
- Complete when: a screen reader can announce current offset, byte, decoded character, selection,
  column, and active inspector value; keyboard-only operation reaches every command; high-contrast
  themes retain caret and selection distinction; and virtualization does not materialize the file.
- Related: B-196, B-047

### B-041 — Selection is limited to one contiguous range

- Evidence: byte selection is now independent from scalar presentation, and a captured drag
  autoscrolls on a timer and ends safely on release or focus loss. The grid still stores only one
  anchor and one caret, with no rectangular or multiple-range model.
- Next: define a bounded range collection and decide how rectangular row slices and independently
  added ranges share copy, export, caret, and search-reveal behavior.
- Complete when: rectangular selection can address repeated row columns, multiple ranges
  copy/export in a documented order, and every command states whether it acts on the primary range
  or the complete collection.
- Related: B-020, B-030

### B-042 — Important hexadecimal commands need first-class actions and shortcuts

- Evidence: the visible command group exposes width, representation, and endian; Go To, row width,
  copy-as-text, copy-as-dump, and select-all are now reachable through a visible compact commands
  button as well as the context menu. Pattern search is discoverable through the shared search
  field, and only byte copy, select-all, and Go To have keyboard shortcuts.
- Next: rank the frequent commands, give each one action identity and shortcut metadata, then expose
  the dominant Go To and copy actions directly in the viewer band.
- Complete when: Go To, bookmark, compare, copy forms, row layout, endian, inspector,
  and analysis panels are reachable without a right click; shortcuts are documented, conflict-free,
  and remappable through the application convention; and the document remains the majority of the
  minimum-size surface.
- Related: B-048

## Tier C — Binary analysis

### B-031 — The viewer cannot calculate checksums or hashes

- Evidence: neither the whole file nor a selected range can be verified from the hexadecimal
  surface, although checksum comparison is a routine integrity and reverse-engineering operation.
- Next: add a cancellable streamed digest job over an explicit byte range and present one result at
  a time before building a multi-algorithm panel.
- Complete when: checksum, CRC32/CRC64, MD5, SHA-1, SHA-256/SHA-512, and BLAKE2 can run over file or
  selection with progress and cancellation, never make the range resident, and copy a result with
  its algorithm and range.

### B-032 — Byte-distribution analysis lacks block-level findings

- Evidence: the analysis action now streams either the current selection or the whole file through
  a cancellable 256 KiB job. Its panel publishes a 256-value byte map with exact hover counts,
  entropy, zero and printable ratios, and a bounded table of inferred ASCII and UTF-16 LE/BE
  strings whose rows navigate back to their exact byte ranges. It does not yet show entropy by
  block or repeated-pattern evidence.
- Next: retain bounded per-block summaries during the same pass, then publish entropy landmarks and
  repeated-block hints that navigate to both occurrences without retaining file-sized state.
- Complete when: histogram, entropy, zero/printable ratios, chunked entropy, repeated-block hints,
  and ASCII/UTF string extraction operate on file or selection, results navigate back to bytes, and
  every analysis remains bounded and labels inference as inference.
- Related: B-024, B-033

### B-038 — There is no safe declarative binary schema for unknown formats

- Evidence: the `Binary` viewer contains curated compiled readers, but a reader cannot describe a
  private or experimental structure without changing and rebuilding Swag Scope. General-purpose
  competitors map declarative structures onto bytes and color their ranges.
- Next: design a deliberately read-only, deterministic schema model with integers, arrays,
  structures, unions, conditions, bounded loops, local endian, and placement at an offset; exclude
  native calls, network, writes, and unbounded execution.
- Complete when: a local schema can parse on demand in bounded work, produces the common
  field/value/offset/meaning tree, colors exact hexadecimal ranges, reports resource limits and
  invalid reads, and never acquires authority beyond reading the open file.
- Related: B-021

### B-039 — Executable bytes cannot be disassembled

- Evidence: PE, ELF, and Mach-O structure readers identify executable regions, but the hexadecimal
  viewer cannot interpret a selected code range or use image metadata to choose architecture,
  address base, and section bounds.
- Next: define a read-only disassembly result contract over an explicit bounded range and evaluate
  which existing backend decoder can serve it without importing an editor or debugger.
- Complete when: supported executable architectures disassemble selected bytes with file offset and
  virtual address, instructions navigate back to exact byte ranges, invalid opcodes advance safely,
  and no execution or process attachment is introduced.
- Related: B-021, B-028

### B-040 — Selected binary data has no domain visualizers

- Evidence: a raw selection cannot be previewed as pixels, palette entries, PCM samples, or a
  numeric series even though Swag Scope already ships reusable image, audio, and plot-capable
  primitives.
- Next: define a viewer-owned, read-only visualization request with explicit type, dimensions,
  stride, endian, and range limits; implement one bitmap and one numeric-plot consumer.
- Complete when: bitmap/palette, PCM waveform, and numeric line/scatter views can visualize a
  selected range without copying the file, invalid dimensions fail locally, and every visualizer
  keeps its source range navigable.

## Quality debt

### B-037 — Existing hexadecimal guarantees lack boundary and interaction tests

- Evidence: current tests cover ordinary and synthetic multi-gigabyte streaming geometry, 16-digit
  offsets, scalar modes, navigation, the named 1 MiB copy bound, search reveal, late short reads,
  byte/nibble/scalar patterns across search-chunk boundaries, invalid search input, visible search
  marks, the compact inspector including binary/octal/boolean readings and file percentage,
  analysis reruns on live selection, rich Go To forms, visible command-menu routing, explicit byte
  order, font zoom/reset, focus-safe mouse capture, non-integer DPI, live English/French wording,
  layout, and dark-theme goldens. Slow-I/O behavior, external file-version changes, and
  accessibility have no deterministic seam yet.
- Next: add the injectable range-reader seam with B-026/B-027, then test delayed completion and
  version changes without timing or filesystem races, and add accessibility coverage with B-035.
- Complete when: those remaining guarantees have deterministic focused tests, generated fixtures
  remain bounded on disk, and future feature entries add their own acceptance coverage instead of
  accumulating here.
- Related: B-049

## Deliberate boundary

Byte replacement, insertion, deletion, replace, undo/redo, save, raw-disk writing, and process-memory
writing are not missing hexadecimal features. Swag Scope is a read-only viewer; those operations
would create a different application and security model. Printing the hexadecimal dump remains the
shared viewer task B-449 in [scope.viewers.md](scope.viewers.md).
