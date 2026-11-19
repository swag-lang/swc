# Swag Scope Log Viewer Backlog

This backlog covers the planned log viewer: event navigation, live following, queries,
structured fields, and timelines across local logs.

### app.scope.log.001 — Log files have no dedicated view

- Evidence: a log opens as Basic text at the beginning. End and Ctrl+End already seek to the file
  tail, but there is no start-at-tail preference, severity/timestamp model or event navigation.
- Next: add a log mode that recognizes common severity and timestamp spellings and groups
  continuation lines into events, with an option to open at the tail.
- Done when: common severity and timestamp spellings are recognized with confidence, the
  reader can start at the tail, entries rather than wrapped screen lines are navigable, multiline
  stack traces remain attached to their event, and uncertain parsing falls back to exact text.

### app.scope.log.002 — Live logs cannot follow append, truncation, or rotation

- Evidence: opening a log snapshots its current size. Services can append, truncate in place, atomically replace, or rotate and
  recreate a path; treating those events alike either loses records or joins unrelated files.
- Next: specialize the host replacement contract with a log cursor carrying file identity, byte
  offset, decoder state, and whether the reader has scrolled away from the tail.
- Done when: append resumes on an encoding boundary, manual scrolling pauses auto-follow,
  truncation and replacement are labelled, rotated predecessors can remain available by explicit
  policy, duplicate/omitted byte ranges are reported, and an idle or hot log stays within fixed CPU
  and memory budgets.
- Related: app.scope.viewers.005

### app.scope.log.003 — Logs have no reusable queries, highlighters, or context filters

- Evidence: the shared query can highlight one expression, but an investigation commonly needs
  several named patterns, include/exclude logic, per-pattern colors, and context around each match.
- Next: layer an immutable event projection over the streamed log index with named query clauses,
  highlight rules, exclusion, and before/after context.
- Done when: literal and regular-expression clauses compose with AND, OR, and NOT; colors remain
  legible in every theme; filtered events retain source offsets and multiline boundaries; counts
  distinguish scanned versus pending input; query sets can be saved without file content; and
  disabling the projection restores source order immediately.
- Related: app.scope.viewers.016, app.scope.text.027

### app.scope.log.004 — Structured logs collapse into undifferentiated lines

- Evidence: JSON Lines, logfmt, key-value prefixes, and common application envelopes carry level,
  timestamp, logger, thread, request, trace, and message fields, but the reader cannot expose,
  select, filter, or correlate them. For JSON Lines, app.scope.json.001 owns the general data tree;
  the log surface owns event-oriented presentation and field conventions.
- Next: define a bounded record/field adapter with JSON Lines first and logfmt second, retaining the
  exact raw event beside normalized fields.
- Done when: detected fields and parse confidence are visible, columns can be selected and
  filtered, nested values remain inspectable, duplicate/malformed fields link to their byte range,
  multiline messages stay intact, and switching back to raw text preserves the event.
- Related: app.scope.json.001

### app.scope.log.005 — Events from several logs cannot share one timeline

- Evidence: failures distributed across client, server, build, and worker logs must be correlated
  manually. File timestamps and embedded timestamps may use different zones, precisions, clock
  skews, or no date at all, so a simple lexical merge would present a false chronology.
- Next: allow an explicit set of local log files to feed one virtual timeline with per-source
  color, parser, timezone, and reversible clock-offset settings.
- Done when: source identity is always visible, timestamp assumptions and unplaced events are
  separated from ordered facts, equal timestamps have deterministic order, filters span sources,
  following remains bounded, and no source file is opened or discovered implicitly.
