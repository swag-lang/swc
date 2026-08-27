# Format Command Backlog

This backlog covers `swc format`, measured against clang-format, rustfmt, gofmt,
prettier, black and `zig fmt`. The compiler that hosts it is
[compiler.md](compiler.md).

Evidence, investigations, and intended outcomes for the command stay together here.
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the command already stands

130 options covering whitespace, indentation, wrapping, braces, switch layout, alignment
(including two-column declaration grids and outlier exclusion), spacing, attributes, comments,
`using` blocks and numeric literals; a built-in canonical style (`--style swag`, the default) with
an explicit opt-out (`--style preserve`) and a `style` key that rebases a config file
([FormatStyle.cpp](../src/Format/FormatStyle.cpp)); a cascading `.swc-format` resolved from the
file's directory upward with parent inheritance
([FormatOptionsLoader.cpp](../src/Format/FormatOptionsLoader.cpp)); `--dump-config`;
`swc-format off`/`on` regions; eleven passes over a token-and-AST model; and C++ tests over 224
cases, the best-tested subsystem in the compiler. On option count it is already in clang-format's
league.

The wrapping contract is settled and written down at the top of
[Pass.Wrap.cpp](../src/Format/Pass.Wrap.cpp): layout is decided locally, one construct and one
break at a time, and the formatter will not gain a penalty model or a document solver. The author
owns the line breaks and the formatter owns the columns — except inside a bracket, where
continuation lines keep their distance to the statement because that is what carries a hand-packed
data table. Reopen that decision only for a wrapping shape that cannot be stated as one local rule.

---

## Automation and editor workflows

### T-016 — Add a CI check mode

`--dry-run` suppresses writes and counts what *would* be rewritten, but there is no check-mode
exit-code contract, no list of differing files, and no optional diff. Add those as one CI-facing
contract. The file list must also expose end-of-line-only rewrites that `git diff` can hide.

### T-115 — Format stdin to stdout

The command only reads paths and writes files in place. Accept a buffer on standard input and
return the formatted result on standard output so an editor can format unsaved content without a
filesystem round trip.

- Related: T-116, T-124

### T-116 — Format a selected source range

Add a line- or offset-based range contract for editor format-selection. Define how the requested
range expands to syntactic boundaries and which returned edits may fall outside it.

- Related: T-115, T-117

## Canonical and resilient formatting

### T-384 — Repair a continuation line the author indented badly

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
- Complete when: a file whose bracket interiors were re-indented at random formats back to the
  committed answer, and `bin/` churn stays nil.
- Related: the wrapping contract at the top of `Pass.Wrap.cpp`

### T-117 — Format source that is temporarily invalid

A file that fails to parse is counted and skipped
([FormatJob.cpp:40](../src/Format/FormatJob.cpp#L40)). Define and implement the token-level recovery
contract needed for format-on-type, without making successful parsing a prerequisite.

- Related: T-115, T-116

---

The entries below were open investigations when the unified backlog was introduced. Their `F-*`
identifiers remain permanent; update their next action in place as the evidence matures. They retain
their former order until re-triaged, so position in this imported block carries no priority claim.

Evidence about defects in the `format` command and its formatting passes.

### F-073 — `swc format` silently skips every path under a dot directory

- Area: compiler
- Found while: validating a `bin/std` change made in a git worktree under `.claude/worktrees/`
- Observation: the file discovery behind `swc format` drops any path holding a segment that starts
  with a dot, and it drops it without a word. `swc tools/format.swgs` run from such a checkout reports
  `formatted 0 files` then `clean`, which reads exactly like a conformant tree. Nothing was read.
- Evidence: with the same `bin/.swc-format` and the same badly formatted source in both places:
  - `swc format -d <scratch>/fmt` reports `1 file • 1 rewritten file` and fixes the file.
  - `swc format -d <scratch>/.dotdir` reports `0 files`. Only the directory name differs.
  - From a worktree at `swc/.claude/worktrees/<name>`, `-d bin`, `-d bin/std`,
    `-d bin/std/modules/truetype/src` and `-f <one file>` all report `0 files`, against a source
    deliberately given six-space indentation and padded `=` signs.
- Why it matters beyond worktrees: the skip is silent and it applies to `-f` as well as to `-d`,
  so a file named explicitly is discarded rather than refused. A tool asked to format one file by
  name that answers `clean` without opening it reports the opposite of what happened.
- Next step: separate two rules that are currently one. Traversal should keep skipping dot
  directories, because `.output`, `.tmp`, `.dep` and `.git` are exactly what it must not walk
  into. A path named explicitly through `-f` should never be filtered. And a run that ends with
  zero inputs should say so: `format.swgs` on an empty selection and `format.swgs` on a conformant
  tree print the same thing today, which is what let this go unnoticed.
- Still live 2026-08-11, and it is not only a reporting problem: an agent working in a worktree
  cannot format at all, so the only way to check a change against the canonical style is to copy
  the files to a path with no dot segment, copy `bin/.swc-format` beside them, format there, and
  copy the result back.

### F-109 — A comment inside a bracket needs two format passes to settle its column

- Area: compiler
- Found while: a mangling campaign over `bin/` sources, feeding `swc format` badly indented but
  valid Swag and checking that one pass reaches a fixed point
- Observation: a whole-line comment sitting between the rows of a multi-line literal reaches its
  final column only on the second run of the formatter, when the rows around it carry indentation
  the formatter preserves rather than recomputes. The output is stable from the second pass on, so
  the only visible effect is that one run is not enough.
- Evidence: take `bin/std/modules/core/src/text/utf8.swg`, re-indent every line inside the `First`
  table at random, and format twice with the canonical style: the first pass leaves
  `// 0x80-0x8F` one column left of the row below it, and the second moves it. Same shape in
  `bin/examples/modules/opengl3/src/main.swg` around `// Right face (+X) - yellow`. Both need the
  rows of one table to disagree about their indentation, which only a rewrite produces.
- Next step: `IndentPass::flushComments` places a pending comment at the column computed for the
  next code line, and `recordHangingLine` then records both against the same anchor. Check whether
  the comment's record is dropped — `canEditGap`, or an anchor that is invalid for a comment line —
  because the code line alone is repaired by `Pass.Align::repairHangingLines`.
- Related: T-384

### F-110 — `column-limit` with `align-operands` needs two format passes

- Area: compiler
- Found while: measuring the greedy wrapper against clang-format on dense expressions
- Observation: the wrapping pass runs after the indent pass, so the continuation lines it creates
  under a column limit are never seen by the pass that would align them on the statement's first
  operand. The alignment lands on the next run.
- Evidence: with `column-limit = 40`, `align-operands = true` and `indent-width = 4`, the body
  `result = compute(alpha, beta) + compute(gamma, delta) + compute(epsilon, zeta)` is broken
  correctly on the first pass, but its operand lines only move under `compute(alpha` on the second.
  With `align-operands` off the same input settles in one pass.
- Next step: either have `Pass.Wrap` record its column-limit breaks as hanging lines the way it now
  records list items and logical operands, or let the indent pass run once more after wrapping and
  own every column. The second is the shape the passes already imply — wrapping decides where the
  breaks are, indentation decides where the lines start — and it would retire the hanging-line
  bookkeeping.
