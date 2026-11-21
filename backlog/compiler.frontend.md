# Compiler Frontend Backlog

This file owns lexer, parser, semantic analysis, type resolution, and diagnostic work. Workspace scheduling and reuse belong in [compiler.build.md](compiler.build.md); code emission belongs in [compiler.codegen.md](compiler.codegen.md).

### compiler.frontend.001 — Imported generic bodies intermittently duplicate a binding

- Evidence: a six-worker DevMode script smoke (`tools/scripts.bat dm smoke`) once stopped
  while checking `asciiart.swgs`. The generated core API's `hashtable.swg` reported local
  `mask` as already defined, and the previous-definition note pointed at the same
  declaration, in specialization `HashTable(string, ConcatBufferPosition)`. Isolated and
  complete reruns passed, and the cause is unestablished.
- Next: the DevMode compiler stops when a conflict names two symbols of one declaration node
  (`SemaError::raiseSymbolConflict`), naming the function. When it fires, replay the cached
  script import alongside module builds from that report. Capture generic-instance
  ownership, parameter-scope restoration and semantic restarts around the binding, and
  compare with the parent compiler before attributing the failure to parsing, publication
  or scheduling.
- Done when: a bounded reproducer identifies the duplicate visitation or publication, the
  root cause is fixed, and the script passes repeated parallel imports with six workers.
- Related: compiler.frontend.004

### compiler.frontend.002 — Isolate a transient null-capture diagnosis in a macro binding

- Evidence: a Release native run once diagnosed twelve null dereferences at `total += seed`
  in `bin/unittests/native/inline/binding_visit_growth.swg`, a diagnostic emitted before the
  micro optimization loops. It failed once with the original session output and work roots,
  then passed with fresh roots and with the same source outside the checkout. Cache or
  work-directory state is therefore not yet separated from scheduling. Repeated filtered
  Release runs with six workers have not reproduced it. Artifact:
  [generated-code session](../bench/disassembly/generated-code/20260916/README.md).
- Next: when it reappears, preserve the failing pre-sanity capture lowering and its output
  and work roots. Then separate cache reuse from shared code-generation state when the
  macro's closure is cloned.
- Done when: a stable reproducer identifies the cause, the correction passes that reproducer
  repeatedly, and the full native suite remains green.

### compiler.frontend.003 — Aligned node references collapse semantic metadata partitions

- Evidence: `NodePayload` selects its shard with `nodeRef.get() % NODE_PAYLOAD_SHARD_NUM`
  (16 shards). The reference is an AST byte offset aligned
  to at least eight bytes, so only two shards receive payload storage or side-table entries.
  Side-table readers answer an absent entry from a per-node bit instead of their shard count
  (folded source symbols excepted). Payload storage writes (`storeMutex`, taken by every stored
  symbol, symbol list and substitute) and every side-table write still contend on those two
  shards.
- Failed attempt: hashing every selector kept generated code identical, but it raised peak
  committed memory (median +17% on `core`, +3% on `gui`) by spreading small payloads over more
  16 KiB pages, with no clear compile-time win.
- Next: separate payload-page allocation from the shard choice, or reduce initial storage
  without reducing the supported contiguous symbol-list size. Compare
  one-worker and parallel rebuilds on both modules under stable load.
- Done when: the partitioning improvement has concurrent read/write coverage and a measured
  compilation-time benefit with its memory cost explicitly bounded.

### compiler.frontend.004 — An imported generic method once lost its own parameter

- Evidence: a forced standard-library rebuild once stopped with `unknown symbol 'arr'` inside
  `Array.opSet(arr: const [..] T) where Reflection.canCopy(T)` of the generated core API
  (`array.swg`), while checking `Array` with `T = u8` for a dependent rebuilt against a
  just-republished core API. The parameter is declared on the line above, and an unchanged
  rerun passed. Isolated replays, `--randomize` seeds and multi-process rounds never
  reproduced it, so the race looks internal to sema of a generic method instantiated from an
  imported API that several modules share.
- Next: the DevMode compiler stops at the wait itself when a body waits on one of its own
  parameters (`Sema::waitIdentifier`), naming the function. When it fires, keep the failing
  process's full log and rerun that exact command under `--randomize --seed` sweeps.
- Done when: the ordering is proved safe by construction or the race is reproduced and fixed
  with a regression case in the `workspace` suite.
- Related: compiler.frontend.001

### compiler.frontend.005 — Reject invalid closure captures without a host exception

- Evidence: while compiling a Swag Capture journey with both a by-reference capture of a `let String` and an unqualified `.main` capture expression, `swc.exe` reported the source diagnostics but also raised `0xC0000005` during semantic parsing at the capture expression. Correcting the source removed the exception.
- Reductions: a by-reference capture of a `let string` and an unqualified `.main` capture
  initializer have standalone expected-diagnostic fixtures. Both report their intended error
  under Linux DevMode and both Windows compilers; neither reproduces the original combination.
- Next: recover the original journey. A standalone closure with both a by-reference `let`
  struct capture and an unqualified `.main` initializer reports the `.main` diagnostic and
  does not reproduce the exception. Retain the matching compiler artifacts on recurrence.
- Done when: the original mixed-capture failure is explained and a regression protects its
  source diagnostics under both compiler executables.

### compiler.frontend.006 — Verify runtime fault evidence across Windows run modes

- Evidence: the [bounds and panic fixtures](../src/Unittest/Compiler/Test.Compiler.Failure.cpp)
  exercise index, slice and count faults in scripts, JIT tests and native tests on Linux.
  Windows needs execution coverage for the same diagnostics and termination paths.
- Next: run the DevMode filesystem tests on Windows. Check that the native runner records
  the failed test and that a script reports the fault once and runs its drop hooks.
- Done when: the decisive values and original source location agree across the three modes,
  and a compile-time panic remains distinguishable from a script runtime panic.
- Related: compiler.command.test.001, compiler.command.002, compiler.safety.032.

### compiler.frontend.007 — Suppress dependent errors while keeping independent diagnostics

- Evidence: [the semantic wait checker](../src/Compiler/Sema/Helpers/SemaCycle.cpp)
  suppresses stalled dependency reports once an error is known. Pending identifier lookups
  still report individually. Ordinary failed aliases, initializers and function signatures
  already leave independent errors visible.
- Next: reduce a cascading error from generic, imported or generated declarations to a
  fixture alongside an independent error. Suppress the dependent lookup only when it can
  be linked to the failed declaration or publication.
- Done when: the primary and independent diagnostics remain visible, with no secondary
  report caused by the failed declaration in that fixture.
- Related: compiler.frontend.006, compiler.query.001, compiler.query.003.
