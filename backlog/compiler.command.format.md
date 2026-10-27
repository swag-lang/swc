# Format Command Backlog

This backlog covers `swc format`, measured against clang-format, rustfmt, gofmt,
prettier, black and `zig fmt`. The compiler that hosts it is
[compiler.core.md](compiler.core.md).

Evidence, investigations, and intended outcomes for the command stay together here.
[README.md](README.md) has the whole layout.


## Entries

### compiler.command.format.002 — Format stdin to stdout

- Evidence: `swc format` only reads paths and rewrites files in place, so an editor cannot
  format an unsaved buffer without a filesystem round trip.
- Next: add a standard-input mode that formats the buffer with the selected style and writes
  the result to standard output, with a distinct exit status for unparsable input.
- Done when: standard input can be formatted to standard output with the selected style,
  without reading or writing a source path. Diagnostics and exit status distinguish invalid
  input, and tests cover an unsaved buffer and an unchanged buffer.
- Related: compiler.command.format.003

### compiler.command.format.005 — Format source that is temporarily invalid

- Evidence: a file that fails to parse is counted and skipped
  ([FormatJob.cpp:36](../src/Format/FormatJob.cpp#L36)), so format-on-type cannot format
  incomplete source.
- Next: define the token-level recovery contract, stating which regions are formatted and
  which are left intact and reported. Implement it without making a successful parse a
  prerequisite.
- Done when: incomplete source can be formatted without dropping or reinterpreting its tokens,
  and unrecoverable regions remain intact with a reported limitation. Tests cover
  representative format-on-type states while valid-source formatting remains stable.
- Related: compiler.command.format.002, compiler.command.format.003

### compiler.command.format.001 — Add a CI check mode

- Evidence: `--dry-run` suppresses writes and counts what would be rewritten. It has no
  check-mode exit-code contract, no list of differing files, and no optional diff, and
  end-of-line-only rewrites, which `git diff` can hide, are not listed.
- Next: add a check mode that writes nothing, lists every differing file including
  line-ending-only differences, exits unsuccessfully on any difference, and optionally
  prints the proposed diff.
- Done when: check mode leaves every input byte unchanged, exits unsuccessfully if any file
  differs, and lists those files including line-ending-only differences. An optional diff
  reports the proposed edits, with command-line regression coverage.

### compiler.command.format.003 — Format a selected source range

- Evidence: `swc format` accepts no line or offset range, so an editor cannot format a
  selection.
- Next: define how a requested range expands to syntactic boundaries and which returned edits
  may fall outside it, then accept a line or offset range.
- Done when: a selected line or offset range yields deterministic edits bounded by the
  documented syntactic expansion and leaves unrelated source unchanged. Editor-style tests
  cover nested and incomplete constructs.
- Related: compiler.command.format.002, compiler.command.format.005

### compiler.command.format.004 — Repair a continuation line the author indented badly

- Evidence: inside a bracket, the indent pass keeps the source distance to the statement (the
  wrapping contract at the top of `Pass.Wrap.cpp`). That keeps hand-packed data tables, but
  it also keeps garbage indentation. Forcing the canonical indent was measured and rejected:
  it flattens nested tables onto one continuation level and strips the leading blank that
  aligns the `1,` rows under the `-1,` ones in `bin/examples/modules/opengl3/src/main.swg`.
  Multiline function bodies used as call arguments can also retain a misplaced brace indent
  after formatting, as in `View.startSlide` in `bin/std/modules/gui/src/controls/optionsheet/view.swg`;
  a standalone equivalent formats correctly.
- Next: implement and measure this criterion: a bracket whose continuation lines already
  share one indent keeps it, and a bracket whose lines disagree is re-indented to the
  canonical continuation column.
- Done when: a file whose bracket interiors were re-indented at random formats back to the
  committed answer, and `bin/` churn stays nil.
