# Formatter Findings

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
