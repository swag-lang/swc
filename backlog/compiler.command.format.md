# Format Command Backlog

This backlog covers `swc format`, measured against clang-format, rustfmt, gofmt,
prettier, black and `zig fmt`. The compiler that hosts it is
[compiler.core.md](compiler.core.md).

Evidence, investigations, and intended outcomes for the command stay together here.
[README.md](README.md) has the whole layout.


## Entries

### compiler.command.format.002 — Format stdin to stdout


The command only reads paths and writes files in place. Accept a buffer on standard input and
return the formatted result on standard output so an editor can format unsaved content without a
filesystem round trip.

- Done when: standard input can be formatted to standard output with the selected style,
  without reading or writing a source path; diagnostics and exit status distinguish invalid input,
  and tests cover an unsaved buffer and an unchanged buffer.

- Related: compiler.command.format.003

### compiler.command.format.005 — Format source that is temporarily invalid


A file that fails to parse is counted and skipped
([FormatJob.cpp:36](../src/Format/FormatJob.cpp#L36)). Define and implement the token-level recovery
contract needed for format-on-type, without making successful parsing a prerequisite.

- Done when: incomplete source can be formatted without dropping or reinterpreting its tokens,
  unrecoverable regions remain intact with a reported limitation, and tests cover representative
  format-on-type states while valid-source formatting remains stable.

- Related: compiler.command.format.002, compiler.command.format.003

### compiler.command.format.001 — Add a CI check mode


`--dry-run` suppresses writes and counts what *would* be rewritten, but there is no check-mode
exit-code contract, no list of differing files, and no optional diff. Add those as one CI-facing
contract. The file list must also expose end-of-line-only rewrites that `git diff` can hide.

- Done when: check mode leaves every input byte unchanged, exits unsuccessfully if any file
  differs, lists those files including line-ending-only differences, and an optional diff reports
  the proposed edits with command-line regression coverage.

### compiler.command.format.003 — Format a selected source range


Add a line- or offset-based range contract for editor format-selection. Define how the requested
range expands to syntactic boundaries and which returned edits may fall outside it.

- Done when: a selected line or offset range yields deterministic edits bounded by the
  documented syntactic expansion, leaves unrelated source unchanged, and editor-style tests cover
  nested and incomplete constructs.

- Related: compiler.command.format.002, compiler.command.format.005

### compiler.command.format.004 — Repair a continuation line the author indented badly

- Intent: a wrongly indented continuation line inside a bracket comes out at a sensible column
  instead of staying where it was written.
- Inside a bracket the indent pass keeps the source distance to the statement, which is what makes
  a hand-packed data table survive; the price is that garbage indentation survives too. Forcing the
  canonical indent instead was measured and rejected: it flattens nested tables onto one
  continuation level and strips the leading blank that aligns the `1,` rows of
  `bin/examples/modules/opengl3/src/main.swg` under the `-1,` ones.
- What is missing is a criterion that separates a column layout from an accident. A candidate: a
  bracket whose continuation lines already share one indent keeps it, and one whose lines disagree
  is re-indented to the canonical continuation column.
- Done when: a file whose bracket interiors were re-indented at random formats back to the
  committed answer, and `bin/` churn stays nil.
- Related: the wrapping contract at the top of `Pass.Wrap.cpp`
