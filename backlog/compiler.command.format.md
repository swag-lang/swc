# Format Command Backlog

This backlog covers `swc format`, measured against clang-format, rustfmt, gofmt,
prettier, black and `zig fmt`. The compiler that hosts it is
[compiler.core.md](compiler.core.md).

Evidence, investigations, and intended outcomes for the command stay together here.
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the command already stands

131 options covering whitespace, indentation, wrapping, braces, switch layout, alignment
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

### compiler.command.format.001 — Add a CI check mode

`--dry-run` suppresses writes and counts what *would* be rewritten, but there is no check-mode
exit-code contract, no list of differing files, and no optional diff. Add those as one CI-facing
contract. The file list must also expose end-of-line-only rewrites that `git diff` can hide.

### compiler.command.format.002 — Format stdin to stdout

The command only reads paths and writes files in place. Accept a buffer on standard input and
return the formatted result on standard output so an editor can format unsaved content without a
filesystem round trip.

- Related: compiler.command.format.003, compiler.core.015

### compiler.command.format.003 — Format a selected source range

Add a line- or offset-based range contract for editor format-selection. Define how the requested
range expands to syntactic boundaries and which returned edits may fall outside it.

- Related: compiler.command.format.002, compiler.command.format.005

## Canonical and resilient formatting

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
- Complete when: a file whose bracket interiors were re-indented at random formats back to the
  committed answer, and `bin/` churn stays nil.
- Related: the wrapping contract at the top of `Pass.Wrap.cpp`

### compiler.command.format.005 — Format source that is temporarily invalid

A file that fails to parse is counted and skipped
([FormatJob.cpp:40](../src/Format/FormatJob.cpp#L40)). Define and implement the token-level recovery
contract needed for format-on-type, without making successful parsing a prerequisite.

- Related: compiler.command.format.002, compiler.command.format.003

---

The entries below were open investigations when the unified backlog was introduced. Update their
next action in place as the evidence matures. They retain their former order until re-triaged, so
position in this imported block carries no priority claim.

Evidence about defects in the `format` command and its formatting passes.

### compiler.command.format.007 — A comment inside a bracket needs two format passes to settle its column

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
- Related: compiler.command.format.004

### compiler.command.format.008 — A `fail` function type gains a space before the closing parenthesis

- Area: compiler
- Found while: the repository-wide format pass of a health reset, reviewing the diff it produced
- Observation: when a function type ending in `fail` is the last thing inside a parenthesis, the
  formatter inserts a space between `fail` and `)`. The result is stable — a second pass changes
  nothing — so the only effect is that canonical output reads `fail )`.
- Evidence: format a file holding
  `#assert(#nameof(#type func(s32)->s32 fail) == "x")` and the line comes back as
  `#assert(#nameof(#type func(s32)->s32 fail ) == "x")`. Three repository sources carry that shape
  today: `bin/unittests/sema/types/lambda.swg` (twice) and
  `bin/unittests/sema/compiler/stringof.swg`.
- Next step: `Pass.Spacing::desiredSpaces` already excludes a closing token after a control
  keyword through `isClosingId`, so the space comes from another rule reached first. Find which
  rule answers for the `(fail, ')')` pair — the classifier gives `AstNodeId::FailExpr` the
  `ControlKeyword` role, and the `fail` of a *function type* is not that node.
- Complete when: formatting the line above leaves `fail)` untouched, and the three sources named
  are canonical without the space.
