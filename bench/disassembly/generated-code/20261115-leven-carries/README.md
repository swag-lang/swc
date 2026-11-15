# Levenshtein carried values

Prompt 2 starts from production revision `7e3f5b7d6c`. Both preserved compilers are
DevMode builds made with GCC 14.2.0 on Linux x86-64. Benchmark programs use Release,
three compiler workers, identical sources, forced regeneration and separate output/cache
roots. Compiler hashes and executable hashes are in [provenance.json](provenance.json).
The compiler build number, benchmark computations, data and timed boundaries are unchanged.

Two local post-allocation rewrites remove redundant carry copies without extending live
ranges or changing spill choices. A load/copy/add becomes a load into the saved register
and an LEA into the offset register, provided the add's flags are dead. An offset/select/copy
can select in its final base register, complementing the condition and forwarding one
intervening store, only when both temporary results die and the store address is independent.
Partial loads, live flags, live alternatives and live offset values retain their contracts.

| Executed Levenshtein cell | Baseline | Candidate |
| --- | ---: | ---: |
| Instructions | 17 | 15 |
| Memory operands | 3 | 3 |
| Calls | 0 | 0 |
| Bytes from loop header through back edge | 61 | 54 |

The baseline native interval is `0x40aa10..0x40aa4b`; the candidate interval is
`0x40dda0..0x40ddd4`, inclusive of the back edge. The original non-debug ELF symbol tables
identify their main functions; no debug build substitutes for the compared code. Full main
assembly, Micro and symbols are compressed beside this report. The checksum is `67441`.
Saved registers, spills, frame size, surrounding memory traffic and copy-loop shape are unchanged.
This is two fewer instructions for every executed dynamic-programming cell, not a measured
runtime improvement.

The existing Linux Clang 17 O2 reference (`cpp-clang/leven`) has the same load/LEA separation
and keeps its selected recurrence value in place. Its archived cell is
`0x1ca0..0x1cd9` (17 instructions, including its different induction update). The source
fingerprints still match. Odin's retained reference vectorizes the outer row copy but retains
bounds branches in the cell. ABI, safety and outer-loop work differ, so these listings do not
establish an overall runtime winner. Snapshot integrity/source verification reports only the
twelve Swag `runtime/attributes.swg` fingerprints as stale; fresh Swag baselines are used here.

## Validation and scope

- 1,702 C++ in-memory tests pass, including executed before/after checks of wrapping offsets,
  partial register loads, live arithmetic flags, signed/unsigned selections, operand order,
  ordinary/indexed stores and both temporary liveness cases. The baseline fails the new
  loaded-value optimization assertion; its other 1,700 tests pass.
- `loop_carried_store_forward.swg`: three tests pass in JIT and native with the DevMode
  compiler/program, including aliases, zero/one/many iterations and descending windows.
- The full twelve-task Release `microdiff.py --verbose` comparison passes every checksum.
  Only Levenshtein's executed task code changes. Atomic overloads swap printed ordinals;
  matching their bodies shows unchanged instructions, not the apparent paired LOSS rows.
  Lambda hashes differ with the compiler's runtime installation path. `__run_expr_*` is
  compile-time `__buildCfg` bridge code with process-dependent call metadata and is absent
  from both linked images; it has unchanged instruction/memory/call counts.
- Every other task kernel and shared runtime body matches after overload/name pairing.
  [Raw comparison](microdiff.txt.gz) and [reviewed differences](normalized-diff.txt.gz)
  retain the apparent changes, including equal-count rows, for inspection.

Each rule examines a fixed local instruction window. It reuses the pass's cached physical
liveness/flag queries; no new global data-flow analysis or unrolling policy is introduced.
Acceptance is static. Timing is **not measured** and this batch is **landed, unconfirmed**.
A comparable Windows full campaign and corrected `run_index` update remain required on a
Windows host; Linux static results must not enter Windows history.
