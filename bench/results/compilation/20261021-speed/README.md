# Structural compilation savings, 2026-10-21

This time-bounded prompt-4 session starts at `4af083bc14`, on
`perf/prompt4-20261021-1614` in an external worktree, and runs until 18:00
Europe/Paris. Validation uses the checkout-local DevMode compiler and at most
six workers after fresh machine-load admission. `SWC_BUILD_NUM` is unchanged.
No timing campaign or profiler is run; compilation-time targets remain unverified.

| Retained change | Compiler work removed | Equivalence and storage evidence |
| --- | --- | --- |
| Allocate stack-displacement scratch without clearing unread entries | An initial eight-byte zero write per instruction | The entry and every first-discovered successor receive their offset before being queued. Later transitions retain that initialized offset, including unknown states. Unreachable slots are never read. Capacity, allocation count, propagation and results are unchanged. The helper loses one `memset`, shrinks from 2,237 to 2,018 code bytes and reserves 208 rather than 224 stack bytes. |
| Walk call-argument register banks once | Rebuilding a temporary layout list and recounting each argument's same-kind predecessors | The existing ABI register-state helper visits parameters in the same declaration order. Return, indirect-argument and call-kind exclusions are unchanged. The classifier shrinks from 1,186 to 817 code bytes and its stack reservation from 272 to 120 bytes. |
| Read compiler-call AST lists without intermediate copies | A child vector and append loop in injection scope discovery; copied argument lists for stringification and tag queries | The same immutable AST chunks retain source order. Injection rejects invalid references when popped, before set insertion. Stringification walks chunks sequentially; tag lookup borrows the three indexed arguments. The three helpers shrink from 1,222/596/1,195 to 739/555/1,088 code bytes, with stack reservations falling from 680/480/1,024 to 384/288/784 bytes. |
| Start dominator passes after their known entry | One root comparison per visited node in each cyclic fixed-point sweep and the child-link walk | Both forward traversal and reverse postorder put the entry first. Its fixed dominator and absent parent link are unchanged; every other node retains its order. The helper shrinks from 3,116 to 3,100 code bytes with the same 264-byte stack reservation and no storage change. |
| Stop scanning uses after a direct upper-half observation | Remaining instruction/operand lookups and unnecessary propagation edges for a value already known to require its upper half | Edges run from a result to its inputs. An edge to an already-observed input cannot add a fact; the initial observation and every edge that can still change a fact remain. Traversal results and vector capacities cannot grow. The helper shrinks from 2,622 to 2,606 code bytes with the same 208-byte stack reservation. |
| Reuse the active semantic visitor's child snapshot | Span decoding in stringification and tag queries; another child collection/copy for compiler diagnostics and unreachable-code checks | These post-node/post-child callbacks use the default, unresolved visitor snapshot. Their AST lists are immutable during the callback, and none of the readers advances the visitor while borrowing it. String/tag/diagnostic/unreachable bodies shrink from 555/1,088/1,436/927 to 433/1,026/1,012/678 bytes; stack reservations fall from 288/784/512/528 to 192/744/224/240 bytes. This supersedes the earlier string/tag borrowed-list readers. |
| Reuse the visitor's multipart AST-generation inputs | Copying and destroying a temporary reference vector before concatenating generated source | The parser constructs either one body or the multipart span, so the multipart callback's children are exactly those parts in order. The borrowed span is consumed before substitution restarts the node. The callback shrinks from 755 to 580 code bytes and its stack reservation from 528 to 240 bytes. |
| Allocate interval-sort indices without zeroing them | One four-byte zero write per interval before the sequential index fill | The index fill completes before sorting, and the same consumed prefix becomes the group-offset table. Allocation count, byte capacity, sorting and node moves are unchanged. The interval walker shrinks from 8,742 to 8,270 code bytes and its stack reservation from 1,200 to 1,152 bytes. Total object code falls from 80,253 to 79,789 bytes with unchanged retained data. |
| Initialize directive-suggestion rows only with their recurrence values | Two initial zero passes per token-name comparison | The predecessor row is filled explicitly and each current row is fully assigned before swapping, including empty operands. The Levenshtein recurrence, candidate order and thresholds are unchanged. The helper shrinks from 704 to 463 code bytes and its stack reservation from 136 to 72 bytes. |

The first batch builds successfully and passes all 1,535 default C++ tests,
including backend stack-frame, promotion and register-allocation coverage.
The default C++ command omits filesystem tests requiring `--dev-full`.

The register-bank batch passes all 1,536 default C++ tests. Its new classifier
test covers every pair of zero through seven integer and floating parameters,
with either bank first, including empty signatures and independent exhaustion.

The compiler-call batch passes the complete native suite: 3,922 tests in the
`devmode` program configuration. Its expected idle, pending and hardware recovery
probes produce their deliberate failures, and the outer tool exits zero. This
also exercises the two preceding backend batches together.

The dominator batch passes all 1,536 default C++ tests, including the existing
48-shape comparison between SSA dominance and instruction-graph dominance,
disconnected graphs, cycles, nonzero entries and stale-snapshot rejection.

The upper-half batch passes all 27 SLP-focused native tests in the `release`
program configuration, where vectorization is enabled. The five-batch milestone
also passes all 1,600 C++ tests with `--dev-full` and all 1,539 JIT tests in
`devmode`. These results describe the combined five-batch compiler source;
the earlier complete native result precedes the dominator and upper-half batches.

The visitor-snapshot batch checks the complete semantic suites: 296 normal and
350 expected-diagnostic inputs, including runtime sources. These stages execute
no runtime `#test` bodies. The native `stringof` case also passes its one test
and compile-time assertions with the DevMode compiler in `devmode`.

The multipart-AST batch checks `sema/compiler/ast.swg`, including its nested
generation and generic multipart assertions (29 normal inputs with runtime).
The error selection contains only 28 runtime inputs and is not error-case
coverage. Its native `operator_index_ptr` consumer passes all ten tests.

The interval-index batch passes all 1,536 default C++ tests, including interval
splitting, spills, call ranges and edge-resolution cases.

The directive-suggestion batch passes `parser_err_invalid_compiler`: the
expected-error selection checks 29 inputs including runtime and covers close
misspellings and distant names. The normal selection contains only runtime
inputs and is not counted as directive-suggestion coverage.

Commands run from the campaign worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe unittest --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native -bc release --file-filter slp --num-cores 6 --rebuild
bin/swc.dm.exe unittest --dev-full --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm jit --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm sema --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter stringof --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm sema --file-filter '\compiler\ast.swg' --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter operator_index_ptr --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm parser --file-filter parser_err_invalid_compiler --num-cores 6 --rebuild
```

C++ validation uses a session-specific temporary/cache root outside all checkouts.
Static object and disassembly inspection establishes code shape, not elapsed-time
or peak-memory performance. Benchmark history and the backlog are unchanged.

Rejected leads: every current natural-loop discovery caller already checks for
backward edges, so adding the same guard to the shared discovery helper would
not remove a live traversal.

An attempted native `--file-filter '\compiler\'` run excluded the runtime
allocator helper used by several selected inputs and failed with missing
`testAlloc`/`testFree` symbols. It is not counted as validation; the complete
native run includes those helpers and passes.
