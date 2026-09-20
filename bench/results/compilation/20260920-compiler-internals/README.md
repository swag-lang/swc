# Compiler-internal compilation iterations, 2026-09-20

All compiler binaries in this campaign are Release `bin/swc.exe` builds. Measurements cap the
compiler at six workers and run the shared-machine admission check before every invocation. The
program workload remains `devmode` where that is the representative full-code-generation target;
no `swc.dm.exe` compiler is used.

## Batch 1: sanitizer check dispatch and converged states

Baseline: `7e76ce305`, build 1032. Candidate: the same compiler plus this batch, build 1033.

The sanitizer used to invoke every enabled check for every micro-instruction. Almost all calls
returned immediately after inspecting the opcode or flags. Each check now declares the instruction
families it can inspect; the sanitizer computes the family mask once per instruction and skips
irrelevant virtual calls. The masks are supersets of the checks' existing predicates. The plain-load
predicate is shared with the use-after-move implementation so those definitions cannot drift.

After the abstract interpretation converges, the checking walk now moves each chain-head state out
of the state table. The table is dead after that point, so copying its maps into the walk state was
unnecessary.

The command below alternates candidate/baseline order and reports the median paired baseline-to-
candidate ratio (`B/A`). Ratios above 1 favor the candidate.

`py -3 bench/compile.py --swc bin/swc.exe --against <baseline>/swc.exe --swc-cores 6 --admit --reps 9 --only core_rebuild`

| Confirmation | Wall B/A | CPU B/A | Commit B/A | Working set B/A |
| --- | ---: | ---: | ---: | ---: |
| First 9 pairs | 1.016 | 1.019 | 1.025 | 1.030 |
| Second 9 pairs | 1.017 | 1.039 | 1.023 | 1.036 |

Both confirmations agree on less elapsed time, process CPU and memory. The conservative claim is a
repeatable 1.6-1.7% wall improvement on `core_rebuild`; CPU improvement varied from 1.9% to 3.9%.

Guardrails:

- `core_touch`, seven pairs: wall 1.037, CPU 1.004, commit 1.023, working set 1.022.
- `hello_build`, fifteen confirmation pairs: wall 0.996 and CPU 1.034. At a 121 ms median the wall
  difference is below the measurement floor and contradicts the favorable CPU result; no small-
  workspace speed claim is made.

Validation:

- Release rebuild: 0 warnings, 0 errors.
- Focused `sanity` suite: 57 passed.
- Full repository Release-compiler sequence: passed, including 1,500 JIT tests, 57 sanitizer tests,
  3,470 native tests, 2,385 standard-module tests, 549 application tests, 479 language-reference
  tests, scripts, and all example/application smokes.

## Batch 2: single-definition register accounting

Baseline: `efa40fe45`, build 1033. Candidate: the same compiler plus this batch, build 1034.

The sanitizer formerly counted definitions in a temporary `unordered_map`, then copied every
register with a count of one into an `unordered_set`. The accepted implementation keeps one
member map with an eight-bit count saturated at two. It removes the second node allocation per
single-definition register, the second hash lookup, and the final traversal of the first map.

Nine alternating `core_rebuild` pairs produced B/A 1.014 wall, 1.003 CPU, 1.006 commit and 1.000
working set. The CPU difference is below the measurement floor, so no percentage speedup is
claimed. The batch is retained as a correctness-certified structural improvement: it performs one
linear instruction scan and maintains one table instead of building two tables and finishing with
a traversal of the first.

Guardrails remained below the measurement floor. Five `core_touch` pairs produced B/A 1.000 wall,
0.997 CPU, 0.988 commit and 0.984 working set. Five `hello_build` pairs produced 1.021 wall, 0.974
CPU, 0.995 commit and 0.991 working set; wall and CPU disagree at a roughly 170 ms median.

An earlier dense-index variant was not retained. It measured B/A 1.014 wall and 1.024 CPU, but its
per-sanitizer direct arrays raised peak memory: commit B/A 0.985 and working set B/A 0.988. The
accepted single-map form preserves the allocation and traversal simplification without that broad
direct-index storage.

Validation repeated after the final Release rebuild: 0 warnings and 0 errors; 57 focused sanitizer
tests passed; the full repository sequence passed with the same compiler, module, application,
reference, script and smoke boundaries listed for batch 1.

## Batch 3: combined sanitizer property scan

Baseline: `51d29721b`, build 1034. Candidate: the same compiler plus this batch, build 1035.

The sanitizer scanned every micro-instruction once to count register definitions and then scanned
the stream again to detect an in-place mutation of the stack-base register. Both properties now
come from the first scan. Their predicates are unchanged; after a mutation is found only its cheap
boolean guard remains, while definition accounting continues through the function.

Five alternating `core_rebuild` pairs, collected during unusually high shared-machine load,
produced B/A 1.035 wall, 1.032 CPU, 1.006 commit and 1.006 working set. Wall and CPU agree, and all
five builds completed. The local proof is independent of that noisy timing: one complete traversal
and its repeated instruction/definition lookups are removed from every sanitized function.

Validation after the final Release rebuild: 0 warnings and 0 errors; 57 focused sanitizer tests
passed; the full repository sequence passed with the same compiler, module, application, reference,
script and smoke boundaries listed for batch 1.
