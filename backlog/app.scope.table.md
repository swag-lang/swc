# Swag Scope Table Viewer Backlog

This backlog covers the read-only table viewer for delimited text and planned support for
fixed-width records. Spreadsheet document viewers have separate
[XLSX](app.scope.xlsx.md) and [ODS](app.scope.ods.md) backlogs.

### app.scope.table.004 — Table type inference is a fixed sample with no override or formatting

- Evidence: each column's kind (text, integer, decimal, or a date written year first) is inferred
  from its first 128 rows and written under its name. A quantity column is aligned on the right in
  mono, sorted by value, summed in the foot and profiled in the information sheet; its cells keep
  their original text. A value past the sample that does not read as a quantity sorts with the
  empty cells, and nothing counts it. Times, booleans, nulls, and units are not recognized, a date
  sorts by its text, so only year-first dates order correctly, and the reader cannot correct a kind
  or choose how values are formatted.
- Next: refine the sampled kind over every row, counting the cells that contradict it, then add a
  per-column kind override and chronological date comparison.
- Done when: inferred kind and contradicting cells are counted, dates and times sort
  chronologically, a kind can be overridden, formats are configurable, and mixed columns degrade
  safely to text.

### app.scope.table.008 — Fixed-width and whitespace-aligned records have no table view

- Evidence: tables require comma, semicolon, tab, or pipe delimiters. Fixed-width exports, aligned
  command output, and space-delimited scientific data therefore remain plain text even when a
  stable column layout is visible, and naïve whitespace splitting would corrupt empty or padded
  fields.
- Next: add an explicit fixed-width mode with ruler-picked boundaries and a sampled whitespace
  detector that never becomes the default without high confidence.
- Done when: boundaries can be added, moved, removed, and named over a bounded preview; source
  columns retain exact byte ranges; proportional fonts cannot disguise alignment; ragged and short
  records publish diagnostics; and the virtual table features operate without rewriting input.
- Related: app.scope.table.001, app.scope.table.002

### app.scope.table.001 — The table viewer is bounded to 32 MiB

- Evidence: the table viewer detects comma, semicolon, tab or pipe separators, understands quoted
  fields and embedded line breaks, keeps its header visible, and virtualizes the GUI rows. It reads
  at most 32 MiB (`FileLimit`) because the parsed source rows are still resident; the streamed
  basic-text viewer remains selectable for a larger file instead of the table exhausting memory.
- Next: stream source rows through a bounded window that resumes quoting state across chunk
  boundaries, and update the row count as the file is indexed.
- Done when: source rows are themselves streamed through a bounded window and the row count is
  updated as the file is indexed, without weakening quoting across chunk boundaries.

### app.scope.table.002 — Delimiter, quoting, header, and encoding decisions cannot be corrected

- Evidence: table detection picks comma, semicolon, tab, or pipe and treats the first row as
  headers. There is no import surface for a custom separator, quote/escape policy, header toggle,
  comment rows, locale, or text encoding.
- Next: expose detected dialect with a live bounded preview and allow the reader to override each
  decision without editing the source.
- Done when: custom one-character delimiters, tab, quote/escape modes, header presence,
  comments, newline policy, and encoding can be changed; detection confidence and parse warnings
  are visible; and the chosen dialect persists.

### app.scope.table.003 — Table columns cannot be filtered, hidden, reordered, or frozen

- Evidence: a click on a column's header sorts the rows on it through a view index over the source
  rows, ascending then descending, quantities by value and words in natural order, empty cells last
  and equal cells in file order. Every column is presented unconditionally and only one sorts at a
  time. Wide or noisy datasets cannot be reduced to the fields and records under investigation.
- Next: add column presentation state and composable value/text filters to that view index, then
  visibility, width, order, frozen leading columns, and a secondary sort.
- Done when: operations stay bounded through app.scope.table.001, source row numbers remain available,
  multi-column stable sort and composable filters can be cleared, and no operation rewrites the file.

### app.scope.table.005 — Table selection and clipboard interchange stop at one cell preview

- Evidence: search can reveal a cell and long cells use a bounded preview. Selected rows copy as
  tab-separated text, quoted where a value holds a tab, a line break or a quote, with or without
  the column names, from Ctrl+C or the lens, and the lens copies the values of the column the
  table is sorted on, one per line in the order shown. There is no column, rectangle or
  discontiguous cell selection, no copy bound, and no export of the visible rows.
- Next: introduce a source-backed cell-range selection model and stream serializers for TSV, CSV,
  JSON Lines, and plain text.
- Done when: keyboard and pointer ranges work across virtual rows, copied data uses a declared
  bound, export does not, long cells are complete in output, and dialect/quoting is correct.

### app.scope.table.006 — Table exploration has no summaries, grouping, or duplicate analysis

- Evidence: the foot sums one quantity column, and the information sheet profiles the first 48
  columns over every row, counted once on the GUI thread the first time it asks: each column's
  kind, its empty cells and, for quantities, their range and mean. Distinct and error counts,
  distributions, top values, duplicate rows and lightweight groups are absent, and the profile
  is not cancellable.
- Next: build cancellable per-column sketches over the row stream, followed by exact calculations
  on demand for one column or filtered subset.
- Done when: statistics state sampled versus exact scope, memory remains bounded for high
  cardinality, duplicate/group results link back to source rows, and analysis can be cancelled.

### app.scope.table.007 — Table navigation has no stable row identity or direct cell address

- Evidence: `:` and a number in the lens go to that row as the row readout counts it, in the
  order on screen. There is no jump to a source row once sorted, to a column, or to an `R:C`
  cell; sorting and filtering from app.scope.table.003 make those coordinate systems diverge.
- Next: define source and view coordinates before adding a name/address box and navigation history.
- Done when: direct jumps identify their coordinate space, headers are searchable, current cell
  and source row remain visible, and back/forward survives sort and filter changes where possible.
