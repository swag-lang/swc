# Structural compilation savings, 2026-10-17

This prompt-4 pass starts at `46c33a053c` on `perf/prompt4-20261017` in an external
worktree. It uses only that worktree's DevMode compiler, with six workers.
`SWC_BUILD_NUM` remains 1173. The existing compilation reports guided selection
of Micro analysis work; no timing, profiling, or benchmark campaign was run.

| Retained change | Compiler work removed | Equivalence argument |
| --- | --- | --- |
| Precompute record-store byte effects (`082309ef7`) | Repeated operand reads, width/mask construction, and immediate-byte scans during record dataflow sweeps; map nodes for reads | Each store has a fixed defined-byte mask and zero-byte mask. Applying those masks produces the same outgoing state. Instructions remain unchanged throughout the analysis. |
| Save record states only for partial stores (`9f8be1e9f`) | State-map lookups and insertions for reads and whole-word writes | Only partial stores consult the saved state when rewriting. The complete access validation and dataflow remain in place. |
| Intersect forward dominators by instruction order | RPO-rank stores for reachable instructions and repeated rank-array reads during intersections | Every edge in this path points forward, so instruction indices have the same ordering as the previously stored ranks. The existing SSA helper now serves both analyses; cyclic graphs retain their previous algorithm. |
| Solve forward-only record states in one sweep (`edf51be1b`) | A second full instruction-and-edge walk that only confirms convergence | Every predecessor of an instruction has already been processed. Graphs with backward edges keep the existing fixed-point loop and iteration limit. A C++ test checks that repeated field stores in a loop retain their byte-clearing operation. |
| Solve forward-only sanitizer liveness in one reverse sweep | Repeating the chain and live-bit matrix walks to confirm unchanged sets | Chain states are numbered in instruction order, so every successor is final before its predecessor is visited. Graphs with backward edges retain their convergence loop. |
| Visit only marked operand-width positions | Tests of unrelated union operands in register allocation and frame compaction | Removing the lowest set mask bit visits the same width operands in the same ascending order. Fixed-width vector opcodes keep their existing early return. |
| Advance the type-info DFS dependency cursor | Rechecking the completed dependency prefix after each descent, plus a separate node-based stack-membership set | The cursor visits dependencies in the same order. Membership and the cursor fit existing entry padding, checked statically; scope cleanup clears membership before a semantic pause releases cache ownership, so a resumed walk starts each unfinished entry from its first dependency. |
| Keep numeric-promotion rows in one allocation | Allocating each of the 16 rows separately, constructing a temporary row vector, and loading a row pointer for every promotion | Each row has the same compile-time width as the builtin numeric list, protected by a static assertion. All cells retain the same computation and row/column indices. The vector control block has the same size. |
| Skip impossible frame-base candidate probes | Looking up physical or floating-point bases and preferred registers in a table containing only virtual integer registers | The existing validity predicates become candidate-kind predicates. The table contents, iteration order, and selection rule are unchanged. |
| Avoid unread byte-swap provenance initialization and copies | Clearing arrays that every successful trace overwrites, copying those arrays before overwriting them again, and materializing a root result used only for immediate comparison | Successful traces still fill all 64 positions; failed traces are never read. Leaf metadata, bit-combination order, near-miss rejection, and emitted swaps are unchanged. |
| Omit the unqualified type-info self-dependency | Appending and subsequently ignoring the current type when it has no qualifiers | The existing qualifier branch appends a dependency only when normalization is needed. Qualified types keep the same dependency and traversal position. |
| Initialize blocked-call flags only with their final target value | Zero-filling the flag array immediately before assigning every entry | Names and graph rows are appended together. Every target flag is assigned before the edge walk adds caller flags; one owned array replaces the single-use vector without widening its storage. |
| Queue incomplete return summaries only on their state transition | Reading and writing queue-membership bytes during completeness propagation | A summary changes from complete to incomplete once. The transition itself prevents duplicate queue entries; the later growing-mask fixpoint retains its membership array and existing queue order. |
| Materialize completeness dependencies only when propagation is needed | Prefix summation, a second dependency walk, and the reverse-edge and cursor allocations when no dependency is missing; a separate seed scan in every case | Missing dependencies seed the same caller-order queue during the existing count walk. Without a seed, completeness cannot fall; with one, the same reverse edges and queue propagate it as before. Temporary storage is released before the mask phase. |
| Write converged upper-half facts directly into their final slots | A per-instruction input-state allocation, its initialization, and a final full copy in the cyclic path | Every instruction starts queued and writes its input fact on each visit. Queries are enabled only after convergence; outgoing facts, requeues and visit order are unchanged. The existing final buffer already has the required slot extent. |
| Share one enum-value lowering buffer within its metadata build | All but the first temporary byte allocation for the values of one enum | The underlying layout has one fixed size. Each value still starts with zero bytes and is fully materialized before the next reset, preserving omitted elements, padding and relocations. Capacity remains that one layout's size. |
| Keep large inline-binding visited sets in a flat key table | Per-node hash allocations and linked-node probing after the first 16 visited nodes | The small path and pending-node order are unchanged. Membership uses the same 32-bit reference identity; a static assertion bounds the optional control object's size. The flat slots replace MSVC's two-iterator buckets and linked reference nodes. |
| Construct AST visitor frames with their final node reference | The second initialization of every newly pushed frame | Member defaults now describe the complete initial state, and emplacement supplies the node reference directly. Restarts assign that same initial state. Object inspection confirms removal of the caller's repeated stores, with one emplacement specialization and unchanged frame fields. |
| Compute each span chunk's layout once | A second header decode and helper call when reading a chunk, repeated alignment when a write fits its current page, and division in the reader's alignment operation | The pointer and count share the same decoded header and aligned offset. The writer recomputes only after moving to a fresh page. Reader alignment is already constrained to a nonzero power of two, so masking gives the same rounded offset. Publication, bounds checks, element counts and storage layout are unchanged. |
| Initialize primitive semantic-view fields only during computation | Constructor stores immediately repeated by `computeInner`, plus an invalid node reference immediately replaced by the resolved reference | The sole constructor always reaches `computeInner`, which initializes every field before its first read or early return. Recomputations retain the same complete reset. Wrapper members and the object layout are unchanged; object inspection confirms removal of the primitive constructor stores. |

The changes preserve traversal order, promotion choices, virtual-register assignment,
instruction rewriting, and graph storage. Existing C++ shape checks cover record
field clearing and zero-byte facts. The dominator oracle compares every possible
entry and node pair against reachability with a node removed, with and without loops;
SSA tests also cover disconnected forward-only roots.

Validation ran from the campaign worktree:

```text
MSBuild.exe swc.sln /t:Build /m:6 /p:Configuration=DevMode /p:Platform=x64 /p:SwcCompileJobs=6 /nologo /v:minimal
bin\swc.dm.exe unittest --num-cores 6 --verbose-unittest
bin\swc.dm.exe --num-cores 6 tools\unittests.swgs dm native -bc devmode --file-filter record_word_paths.swg --num-cores 6 --rebuild
bin\swc.dm.exe --num-cores 6 tools\unittests.swgs dm native -bc devmode --file-filter optimizer --num-cores 6 --rebuild
```

The first build, 1,419 C++ tests, and the single native record test passed before
integrating the first batch. An incremental DevMode build and a fresh 1,419-test
C++ run then passed with all three changes. These are the default internal C++
tests; 60 filesystem tests requiring `--dev-full` were excluded. The final native optimizer selection
checked 289 inputs including the runtime and passed 299 tests. Every command exited
zero. The native tool invocations used separate external `TEMP`/`TMP` cache roots.
Machine-load admission preceded each build and test. Formatting and `git diff --check`
also passed. No broader repository campaign or Release-compiler build was needed
for these local analysis changes.

The continuation starts after importing `3392a220bc`. The record-state batch passed
1,421 C++ tests and the one native record test. The sanitizer batch passed 1,421 C++
tests and all 85 `sanity` tests, using the same commands above with `sanity` replacing
`native` and without a file filter. Both builds and all commands exited zero.

The six-change checkpoint passed 1,421 C++ tests, the complete native suite
(3,888 tests and the expected idle/pending/hardware recovery probes), and the complete
JIT suite (1,539 tests). All commands exited zero, using the commands above without
native file filters and with `jit` selecting that suite. All program configurations
were `devmode`, driven by the worktree-local DevMode compiler.

The type-info traversal batch passed 1,421 C++ tests, 16 JIT reflection tests
(`--file-filter reflection`), and 57 native metadata tests (`--file-filter typeinfo`).
The build and all commands exited zero. These checks include recursive type metadata,
dynamic constraints, attributes, and lifecycle reflection; the cache ownership and
payload-publication protocol are unchanged.

The promotion-row batch, including the synchronized constant-slice-countdown change
from `master`, passed 1,423 C++ tests. Its new numeric-pair test covers all 16 builtin
categories in both operand orders and the minimum-32-bit rule. Semantic checking
with `--file-filter arithmetic.swg` checked three standalone arithmetic sources
plus the runtime (31 inputs); no expected-error source matched that filter. The
native `--file-filter constant_slice_countdown.swg` integration check passed one
test. All builds and commands exited zero in DevMode.

The eleven-change checkpoint passed 1,423 C++ tests, the complete native suite
(3,889 tests and expected recovery probes), and all 1,539 JIT tests, all driven by
the DevMode compiler in program configuration `devmode`. The byte-swap cases cover
32- and 64-bit inputs, reordered terms, and near misses. The metadata cases cover
qualified and recursive types. The three latest local changes were validated
together before retention; all builds and commands exited zero.

The blocked-call initialization batch passed 1,423 C++ tests and the native
`inline_auto_relaxed_constructs.swg` test. Existing C++ inlining checks cover
recursive components, blocked direct calls, nested functions, and separate ASTs.
The incremental DevMode build and both test commands exited zero.

The return-summary queue batch passed 1,423 C++ tests, including guarded aliases,
recursive summaries and unresolved dependencies, and all 85 sanity tests. Its
incremental DevMode build and both commands exited zero. The first two admissions
were deferred for CPU load; neither deferred test was started.

The completeness-graph batch passed 1,423 C++ tests and all 85 sanity tests after
an incremental DevMode build. All commands exited zero. Guarded-summary coverage
includes both fully resolved graphs and a dependency that completes on a later call.

The upper-half slot batch passed 1,424 C++ tests and the native `dword_joins.swg`
test. The new C++ loop case checks both a 32-bit backedge, which permits removing
the clear, and a 64-bit backedge, which requires retaining it. The incremental
DevMode build and both commands exited zero.

The sixteen-change checkpoint passed 1,424 C++ tests, 3,889 native tests with the
expected recovery probes, and 1,539 JIT tests. The enum-focused
`typeinfo_collections.swg` check passed two tests before the broad suites. The
DevMode build and all commands exited zero.

The large inline-binding batch passed 1,424 C++ tests and its new native test,
which passes a 32-term expression through explicit inlining. The focused semantic
`local_function` selection checked four expected-error sources plus the runtime;
no normal semantic source matched. The new source was formatted. The DevMode
build and all test commands exited zero.

The AST-frame batch passed 1,424 C++ tests and all 1,539 JIT tests after its
DevMode build. The existing visitor tests cover pauses, skipped children, restarts,
resolved ancestors and pending siblings. An initial JIT `compiler` file filter
failed because it omitted `runtime/default_allocator_helpers.swg`; the corrected
whole-suite command retained those required inputs and exited zero. These tests
used the frame-change binary before the following span changes were built.

The span-layout batch passed 1,425 C++ tests and 16 JIT reflection tests after
the final DevMode build. Its new C++ case checks empty, single-page and cross-page
spans at several page-prefix offsets, using the API's maximum supported alignment.
Object inspection confirms one chunk-layout helper call and a mask-based reader
alignment. Both builds and all test commands exited zero.

The compilation-time targets remain unverified. This is not a claim that the speed
campaign has exhausted every possible structural saving.
Worklist visitation changes were left aside because changed early-exit priority
would require measurement to establish a saving.
An additional register-kind predicate on every definition was also left aside:
only refining the already-required base and preferred-register predicates avoids
an extra test on valid candidate definitions.
