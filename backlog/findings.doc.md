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
  no sema artifact it could reuse.
- Next step: measure which compile-time callers demand the 7 803 JIT emissions during a doc run,
  and whether any lowering is demanded by paths documentation never needs; that number bounds
  what any doc-mode fast path could save before the larger incrementality work.

### F-130 — Export-root resolution walks the declaration tree once per symbol

- Area: compiler
- Found while: removing the per-symbol whole-AST scans this entry originally described
- Observation: the memoized `Ast::reachableNodeRef` index removed the dominant scan (`ogl`
  `collectDocItems` 803 ms to ~190 ms, its doc stage 1 159 ms to ~315 ms, and the same index
  serves `collectPublicEntries` inside sema), but the collector still resolves each item's
  export root through `findExportDeclRoot`, whose `collectModuleApiNodePath` runs a
  root-to-target DFS over the declaration tree for every symbol. A generated binding file with
  thousands of top-level declarations pays declarations-times-tree-size again there; it is the
  main suspected share of `ogl`'s remaining ~190 ms collect.
- Evidence: [ModuleApi.Decl.cpp:32](../src/Compiler/ModuleApi/ModuleApi.Decl.cpp#L32)
  (`collectModuleApiNodePath`), reached per candidate from
  [DocApi.Collect.cpp:864](../src/Doc/DocApi.Collect.cpp#L864); measured with the F-129 probes
  after the reachable-index fix.
- Next step: record each node's parent in the same single traversal that builds
  `Ast::ReachableNodeIndex` and derive the root-to-target path by walking parents upward,
  keeping the additional-node and function-body constraints as per-ancestor checks; re-measure
  `ogl` collect.
- Related: F-129
