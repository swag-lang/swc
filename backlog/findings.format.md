# Formatter Findings

Evidence about defects in the `format` command and its formatting passes.

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
