# Test Command Backlog

This file owns test selection and failure reports provided by compiler test commands.

### compiler.command.test.001 — Rerun one failed test by stable identity

- Evidence: file and tag filters and per-test events already exist. An
  [anonymous JIT test](../src/Main/Command/Command.Test.cpp#L675) is reported with its source
  location, but moving it changes that identity and a file filter can rerun its neighbors.
- Next: add an explicit test name or stable ID, with exact selection and a printed
  reproduction command carrying its workspace, module, effective preset, backend and
  explicit test inputs. Summarize selected, executed, failed and unexecuted tests,
  distinguishing a failed test from later tests skipped when the run had to stop.
- Done when: a printed command reruns one reported failure after a line-only edit and
  the result clearly identifies unmatched selections and incomplete runs in JIT and native.
- Related: compiler.frontend.006, compiler.command.test.002, compiler.command.002.

### compiler.command.test.002 — Show both values of a failed test comparison

- Evidence: `Swag.check(actual == expected)` reports the expression but gives no values
  for a failure such as 11 versus 10. [Existing verdicts](../bin/runtime/intrinsics.swg#L14)
  already distinguish stopping at a failure from recording it and continuing.
- Next: add a comparison assertion or a lowering of comparisons in test checks that
  captures each operand once and prints bounded values on failure. Start with scalars and
  strings, then locate the first differing element of a sequence.
- Done when: the report includes actual and expected values at the same source location
  in JIT and native tests, and evaluation-order tests prove operands and overloaded
  comparisons execute exactly once.
- Related: compiler.frontend.006, compiler.command.test.001.
