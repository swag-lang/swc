# Findings — Doc

The `doc` command: what a documentation run collects, what it renders, and what it costs. Intent
for the same unit is [todo.doc.md](todo.doc.md).

What belongs here is what the documentation pipeline itself does — collection, rendering, and the
price of a run. A frontend, semantic-analysis, or code-generation defect that a documentation run
merely exposed belongs in [findings.compiler.md](findings.compiler.md): the file follows the fix,
not the discovery.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-129 — A documentation run spends nine tenths of its time re-running sema

- Area: compiler
- Found while: investigating why some documentation pages take several seconds to generate
- Observation: `swc doc` runs full workspace sema on every invocation, with or without
  `--rebuild`, and the per-module stage line the user reads as "doc time" is dominated by it.
  The page generation itself is small: with the reachable-node index in place, the doc side of
  the whole `std` workspace is under 1 s of a ~8 s wall run (instrumented build, 22 workers), and no
  single module keeps a doc stage above ~0.3 s. Inside the sema time, compile-time execution
  JIT-emits 7 803 functions: session timers report 77 s CPU of semantic analysis plus 24.5 s CPU
  codegen and 21.7 s CPU micro lowering, against 2.7 s parser and 0.7 s lexer. Each module also
  re-analyzes its dependencies' exported public API (`ogl` has 29 own sources but sema
  processes 133 files).
- Evidence: an instrumented `swc doc --workspace bin/std --doc-output-dir <tmp> --rebuild` run,
  with timing probes around `Command::doc`'s sema call and inside
  `DocApi::generate` ([Command.Doc.cpp](../src/Main/Command/Command.Doc.cpp),
  [DocApi.cpp](../src/Doc/DocApi.cpp)). Omitting `--rebuild` changes nothing: a doc run persists
  no sema artifact it could reuse. A later six-worker DevMode probe counted 10 877 JIT
  preparation roots across `std`: 6 929 constant calls, 702 constant-set calls, 2 608 immediate
  statements, 263 run expressions, 210 function results, and 165 statements. The hottest roots
  were `isStruct` (3 092), `__message_0` (2 605 immediate statements), `isEnum` (1 239),
  `fromArgb` (644), and `fourCc` (581). Suppressing optional constant folding for `doc` changed
  no measurable wall time (25.66 s versus a 25.25 s baseline), so that experiment was reverted:
  repeated preparation requests are not evidence that they emit or lower a function again.
- Next step: attribute each newly emitted function and its lowering CPU to the first JIT root and
  dependency closure that demanded it, excluding already-ready preparations. Start with the
  `isStruct`/`isEnum` closures and the repeated `__message_0` path; only then decide whether a
  doc-mode fast path exists. Persisting sema and codegen across invocations remains T-002/T-122.
- Related: T-002, T-122
