# Semantic analysis and code generation work reductions, 2026-09-13

This change removes repeated work outside the micro passes. Functional validation targets
compiler builds 532 through 542 on `1cb02fdaa` plus the changes below. Work is isolated on
`perf/sema-codegen-compile-time` in the `swc-sema-codegen-perf` worktree. Micro-pass work has its own
[report](../20260913/README.md).

Timing measurements are deferred at the user's request because the shared machine is busy.
This report makes no measured compilation-speed claim; a performance campaign will follow
separately.

## Retained changes

| Area | Removed work | Preserved contract |
| --- | --- | --- |
| Semantic context frames | Ordinary AST nodes no longer copy the complete `SemaFrame`. Nodes introducing a context copy once instead of twice. | Contexts retain the same node boundaries and syntax, compiler-evaluation, and generated-top-level markers. |
| Physical scopes | Cached depth replaces parent walks. Owned-scope indexing replaces repeated searches during child-analysis scope remapping. The copied scope vector reserves its final size. | Physical depth remains independent of redirected macro/mixin lookup parents. Pointer identity distinguishes foreign scopes at the same depth. The depth field occupies existing alignment padding. |
| Generic instances | Caches of at most eight instances retain linear lookup. Larger families build a lazy hash-to-vector-index table. | Full argument equality resolves collisions. Numeric indices survive vector relocation. Reverse lookup retains the original argument storage. Small caches add one pointer and a branch, without a new hash-table allocation. |
| Temporary cleanup and inline contexts | Code generation removes retired temporary suffixes. Duplicate registration returns before ancestor discovery. Inline-context setup reuses an existing matching-frame search result. | Live entries retain their order; canceled interior entries remain until the suffix retires. Destruction order and inline return-label ownership are unchanged. |

The new C++ test `Sema_GenericInstanceStoragePreservesIdentityAcrossGrowth` inserts 512
distinct identities, alternating inline and heap-backed argument vectors. It checks retrieval
after growth, reverse lookup, duplicate argument and symbol handling, argument order, and an
empty argument list. The implementation checks exact equality for hash collisions; the test
does not force a particular collision.

A functional stress input with 4,096 separate temporary-producing statements also passed
on the preceding build 526, checking 4,096 constructions, 4,096 destructions, and a
destruction checksum of 8,390,656 ([log](temporary-stress.log)).

## Functional validation

Both integrated build-532 compiler configurations, DevMode and Release, built successfully.
All commands below exited with code 0 on the integrated DevMode compiler.

| Complete suite | Result | Evidence |
| --- | --- | --- |
| C++ | 674 passed, including the new generic-storage test | [Log](cpp-532.log) |
| Semantic analysis | 278 valid inputs and 293 expected-error inputs verified | [Log](sema-532.log) |
| JIT | 1,394 passed | [Log](jit-532.log) |
| Native, program configuration `devmode` | 3,131 passed; generated executable passed | [Log](native-devmode-532.log) |
| Native, program configuration `release` | 3,131 passed; generated executable passed | [Log](native-release-532.log) |

The C++ invocation does not select the 28 filesystem tests requiring `--dev-full`.
The native suite includes temporary destruction, inline receiver lifetime, and deferred
reemission; the JIT suite includes narrowing, macro scopes, and variadic mixin closures.

Commands use the checkout-local compiler and cap both tool and child compiler workers:

```powershell
bin/swc.dm.exe unittest --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm sema --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm jit --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native -bc devmode --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native -bc release --num-cores 6
```

The user waived machine-load admission for this session; all worker caps were retained.

## Additional reductions in build 533

| Area | Removed work | Preserved contract |
| --- | --- | --- |
| Inline argument analysis | One body traversal summarizes all parameter uses instead of repeating searches for every parameter and every usage category. | The summary belongs to one expansion and uses the existing cross-AST and injected-code traversal. Counts saturate at two; address, mutation, indexing, foreach, and pointer-level uses retain their previous definitions. Code-only expansions do not allocate the summary. |
| Move elision | A block stack replaces ancestor walks for local declarations. Variables already known to escape skip repeated escape classification. | Every use still updates its last-use position; defer and closure tracking remain active. Block exit restores the enclosing declaration context. |
| Call candidates | Candidate collection no longer deduplicates a second time. | The owning candidate list already enforces uniqueness. Discovery order, priority, and callable filtering remain unchanged. |
| Completed frees summaries | Calls without return guards skip both return-summary fixed points. Ineligible forwarding edges and resolved guards are filtered before frees propagation. | Guarded calls retain both return-summary fixed points. Forwarding order and live completion checks remain unchanged. |
| Read-only data collection | Each reachable allocation retains its immutable source extent and first owner. Collection reuses stable map entries and avoids a separate emitted-allocation list. | Relocations are still read at their original stages, including dependencies appended after initial collection. Emission remains ordered by shard and source offset. |
| Data segments | Large-block offset lookup uses binary search. A range of unique relocations already in order avoids another sort. | The paged prefix keeps its constant-time rejection path. Matching unsorted tails and duplicate offsets retain the historical sorting behavior. |

The new C++ regressions cover candidate identity and order, direct and guarded frees propagation,
128 growing cyclic constant dependencies across two shards, aligned large allocations with a paged
prefix, and relocation ranges containing indexed entries, unsorted tails, and equal offsets.

The new JIT/native inline tests cover repeated rvalues, independent expansions, read-only address
taking, slice element mutation, count-only and consumed variadic packs, and indexed arguments with
side effects. The native move tests cover restoration after nested blocks and deferred observation
of an already escaped variable. An initially invalid test that reassigned a read-only scalar
parameter was corrected to use local mutable copies; compiler semantics were not relaxed.

Build-533 validation uses the same worker caps and commands as build 532. Both compiler
configurations built successfully. The full C++ suite passed 680 tests; the same 28 filesystem
tests remain outside this selection. Focused DevMode tests passed for `binding_usage_summary.swg`
(3 JIT and 3 native tests), `move_drop_elision.swg` (8), `return_move_out.swg` (11), and
`jit_use_after_free_summary.swg` (static checks). The Release compiler also passed the native
binding summary (3) and `address_constant_storage.swg` (1), with six workers.

| Build-533 complete suite | Result | Evidence |
| --- | --- | --- |
| C++ | 680 passed | [Log](cpp-533.log) |
| Semantic analysis | 278 valid inputs and 293 expected-error inputs verified | [Log](sema-533.log) |
| JIT | 1,397 passed | [Log](jit-533.log) |
| Native, program configuration `devmode` | 3,136 passed; generated executable passed | [Log](native-devmode-533.log) |
| Native, program configuration `release` | 3,136 passed; generated executable passed | [Log](native-release-533.log) |

Focused evidence: [JIT bindings](jit-binding-533.log), [native bindings](native-binding-533.log),
[move elision](native-move-533.log), [return move](native-return-533.log),
[static use-after-free checks](sanity-free-533.log), [Release-compiler bindings](release-compiler-binding-533.log),
and [Release-compiler constant addresses](release-compiler-rdata-533.log).

## Additional reductions in build 534

| Area | Removed work | Preserved contract |
| --- | --- | --- |
| AST traversal | Completed child ranges are retired from the traversal stack. Identity resolutions skip the active-ancestor scan. | Pause, skip, restart, replacement, and active-ancestor handling retain their callback order. Borrowed child views last only until traversal advances. |
| Literal contexts | Child callbacks borrow the visitor's collected range; array binding uses the current child index. | Struct member mapping and contextual sibling inference retain their previous behavior. |
| Aggregate concretization | Constant values and dimensions are passed through spans instead of copied into intermediate vectors. | Scalar promotion, constant fitting, and nested array shape deduction are unchanged. |
| Inline binding validation | Visited sets stay inline for up to 16 nodes, then switch to hashed membership. | Nested function validation shares the same visited identity and traversal order. |
| Generic aggregate matching | An extra assigned-entry buffer is removed. | Named entries are already excluded from the monotonically advancing positional cursor. Duplicate and missing members retain their checks. |
| Index and string-switch lowering | Index addressing reuses the computed result type. A switch split search stops once every case is distinguishable. | Array, pointer, SIMD, string, and variadic element sizes are unchanged; split ties still retain the first candidate. |
| Native preparation | Function names and artifact lookup tables are built once after lowering and executable pruning stabilize. | Code generation uses the same symbol order and completion barriers. JIT retains the complete lowered segment. Missing-code diagnostics construct their metadata on demand. |

Two C++ visitor regressions exercise pauses at each callback boundary, skipped children, restarted
nodes, sibling preservation, substituted children, and ancestor-resolution rejection. New JIT
fixtures cover contextual literals and closure binding traversal beyond inline visited storage;
the latter also runs natively. The literal test keeps the existing `s32` concretization of an
unannotated scalar field and the existing constant-fitting behavior of nested `u8` arrays.

Both build-534 compiler configurations built successfully. The full C++ selection passed 682
tests, with the same 28 filesystem tests excluded. Semantic analysis verified 278 valid and 293
expected-error inputs. The full JIT suite passed 1,400 tests.

Focused DevMode checks passed for literal context (2 JIT tests), binding growth (1 JIT and 1
native test), aggregate field order, union deduction, array sibling binding, index lists (3),
dereferenced indexing (9), collection casts (1), untyped variadics (2), typed variadics (4), SIMD
lanes (1), and switch dispatch (17). The Release compiler passed the native index-list (3),
switch-dispatch (17), and binding-growth (1) fixtures, all with six workers.

| Build-534 complete suite | Result | Evidence |
| --- | --- | --- |
| C++ | 682 passed | [Log](cpp-534.log) |
| Semantic analysis | 278 valid inputs and 293 expected-error inputs verified | [Log](sema-534.log) |
| JIT | 1,400 passed | [Log](jit-534.log) |
| Native, program configuration `devmode` | 3,137 passed; generated executable passed | [Log](native-devmode-534.log) |
| Native, program configuration `release` | 3,137 passed; generated executable passed | [Log](native-release-534.log) |

Focused evidence: [literal contexts](jit-literal-context-534.log),
[JIT binding growth](jit-binding-growth-534.log), [native binding growth](native-binding-growth-534.log),
[Release-compiler indexing](release-compiler-index_list-534.log),
[Release-compiler dispatch](release-compiler-switch_dispatch-534.log),
and [Release-compiler binding growth](release-compiler-binding_visit_growth-534.log).

## Additional reductions in build 535

| Area | Removed work | Preserved contract |
| --- | --- | --- |
| Named literal binding | A named child resolves its own target member directly instead of rebuilding the assignment history of preceding children. | Positional binding and escape-analysis member mapping keep the existing ordered assignment algorithm. |
| Large struct lookup | Completed structs with more than 32 fields reuse their existing symbol index. | The result must belong to the struct's field-index map; ignored, non-field, or synthetic cases fall back to the original scan. Small and incomplete structs keep that scan. |
| Aggregate type storage | The unused source-reference vector is removed from aggregate type payloads. | Types and member names retain their ownership and copy/move/destruction behavior. Runtime reflection has a separate representation. |
| Aggregate type hashing | The internal hash includes ordered type and name handles, replacing one hash per arity. | Exact equality still resolves collisions. Runtime hashes and structural shard selection in a configured compiler are unchanged. |
| Constant assignment checks | Parenthesized expressions no longer build an unused semantic view; indexed sources avoid a duplicate inline-constant check. | The same recursive constness predicates and diagnostics remain active. |
| Final executable dependencies | Call and constant traversals retain independent cursors, one function set, and one visited-allocation set across closure iterations. | This state is retained only after all lowering completes. Earlier lowering rounds still rescan with fresh state. Discovery order, duplicate roots, constant recursion, and final pruning are preserved. |

The new type-interning regression checks 256 distinct same-arity inputs in each of three families,
with independently varied types and names, temporary inputs, copying, moving, permutations, and
retrieval after growth. It allows hash collisions while rejecting a single hash for the whole family.

The native dependency regression verifies an alternating chain of direct calls and constant
function tables. It checks actual `ConstantAddress` and `FunctionSymbol` relocations, duplicate
global roots, unique retained functions, and an unreachable function that was lowered before pruning.
The C++ fixture installs the lowered graph directly after semantic analysis; it does not depend on
source-language constant folding of function addresses.
The large-struct JIT fixture covers 34 fields, an ignored declaration, reversed named binding,
partial initialization, inline cloning, and a positional prefix followed by reordered named fields.

Both build-535 compiler configurations built successfully. The same 28 filesystem C++ tests remain
outside this selection. Focused DevMode tests cover literal contexts, aggregate field order,
constant slices, promoted field lookup, and constant assignment diagnostics. The Release compiler
passed large-struct binding (2 JIT tests), constant slices (6 native tests), and constant-address
storage (1 native test), with six workers.

| Build-535 complete suite | Result | Evidence |
| --- | --- | --- |
| C++ | 684 passed | [Log](cpp-535.log) |
| Semantic analysis | 278 valid inputs and 293 expected-error inputs verified | [Log](sema-535.log) |
| JIT | 1,402 passed | [Log](jit-535.log) |
| Native, program configuration `devmode` | 3,137 passed; generated executable passed | [Log](native-devmode-535.log) |
| Native, program configuration `release` | 3,137 passed; generated executable passed | [Log](native-release-535.log) |

Focused evidence: [large structs](jit-large_struct_named_binding-535.log),
[JIT constant slices](jit-const_slice-535.log), [native constant slices](native-const_slice-535.log),
[Release-compiler large structs](release-compiler-large-struct-535.log),
[Release-compiler constant slices](release-compiler-const-slice-535.log), and
[Release-compiler constant addresses](release-compiler-rdata-535.log).

## Additional reductions in build 537

| Area | Removed work | Preserved contract |
| --- | --- | --- |
| Type interning | The intern table owns the single arena-resident type instead of keeping another full key copy. | Transparent lookup retains exact hash/equality, shard selection, stable addresses, and the shared/exclusive locking protocol. The complete reference, including its diagnostic pointer, is published before readers can observe it. |
| Type payload lifetime | The canonical table destroys owned type payloads before arena pages are freed. | Array dimensions, index types, and aggregate vectors are released exactly once; direct handle-to-arena access is unchanged. |
| Constant preparation | Aggregate hits no longer copy their element vectors twice before lookup. | Mutable preparation remains local for pointers and borrowed spans. One atomic location snapshot governs lookup, enrichment, and publication. Relocatable borrowed payloads remain distinct. |
| Inline temporary ownership | Inherited frames carrying the same inline payload do not repeat argument and ancestor searches. | A different nonempty payload is still examined in frame order. No frame state or persistent cache is added. |
| Runtime module order | A minimum heap replaces a full scan for every next ready module. | The lowest eligible input index still wins. Cycles and their blocked dependents retain the original input-order fallback; destruction reverses initialization. |
| Executable roots | The existing dependency set also compacts repeated roots before traversal. | First occurrences and subsequent dependency discovery order are stable, including distinct symbols with equal source locations. |

The isolated type-payload destruction test first ran against build 536, before the owning-table
change. It was the only failing test: 684 passed and one failed. Build 536 was an intermediate
validation binary, not a retained implementation or a timing baseline. The test counts live blocks
in a dedicated mimalloc heap; it does not compare process memory or compilation time.

Additional regressions race two type-interning threads across table growth, retain pointers
to old entries, and check references returned by later hits. Constant tests destroy their temporary
aggregate inputs and verify that storage enrichment does not mutate borrowed-span or pointer inputs.
The runtime-order regression covers priority changes, repeated imports, absent and self imports,
cycles, blocked modules, reverse destruction, and a second preparation with no imports.

Both build-537 compiler configurations built successfully. The C++ suite passed 689 tests,
including the unchanged type-payload test that failed before the owning-table correction.
The same 28 filesystem tests remain excluded. Focused native checks passed for temporary receiver
lifetime (2), caller-expression arguments (1), automatic macro receivers (1), indexed macro
receivers (1), deferred re-emission (2), and constant slices (6). The deferred test requires both
`defer_reemission.swg` and `defer_reemission_provider.swg`; the filter is `defer_reemission`.
The Release compiler passed large-struct binding (2 JIT tests), constant slices (6 native tests),
and constant-address storage (1 native test).

| Build-537 complete suite | Result | Evidence |
| --- | --- | --- |
| C++ | 689 passed | [Log](cpp-537.log) |
| Semantic analysis | 278 valid inputs and 293 expected-error inputs verified | [Log](sema-537.log) |
| JIT | 1,402 passed | [Log](jit-537.log) |
| Native, program configuration `devmode` | 3,137 passed; generated executable passed | [Log](native-devmode-537.log) |
| Native, program configuration `release` | 3,137 passed; generated executable passed | [Log](native-release-537.log) |

The first semantic command collided with another process rebuilding the tool's standard-library
dependencies. Its serialized retry passed without a source change. The missing generated API files
and the remaining investigation are recorded as [compiler.core.042](../../../../backlog/compiler.core.md#compilercore042--protect-generated-module-apis-from-concurrent-workspace-rebuilds).
Subsequent tool-driven validation is serialized to avoid overlapping writes to those shared outputs.

The workspace consumer was rebuilt and run separately by each compiler with
`run --workspace bin/unittests/workspace --workspace-module consumer_exe --rebuild --num-cores 6`.
Both runs rebuilt three standard dependencies and six local modules, executed the consumer's main,
and passed initialization and destruction assertions across static libraries and a DLL:
[DevMode compiler](workspace-consumer-537.log), [Release compiler](release-compiler-workspace-consumer-537.log).
This focused consumer exercises the changed runtime order; the broader workspace command campaign
was not run.

## Additional reductions in build 539

| Area | Removed work | Preserved contract |
| --- | --- | --- |
| Constant interning | The intern table owns the arena-resident constant instead of retaining another deep key copy. | Transparent lookup retains value equality, shard and stripe routing, stable addresses, and the shared/exclusive locking protocol. Owning aggregate payloads are destroyed before their segment pages are freed. |
| Constant publication | References are finalized before their canonical entries become visible. | Both insertions and later hits carry the diagnostic pointer. Atomic storage-location enrichment remains outside hash/equality and does not mutate caller inputs. |
| Same-file symbol order | Symbols from one source file are sorted directly by token index without allocating textual location keys. | Numeric order matches the old ten-digit token suffix. Stable ties, adjacent pointer deduplication, null filtering, and the complete multi-file fallback are preserved. |
| Constant array conversion | Two conversion paths build their final element vector directly. | Element casts, failure handling, and lowering order are unchanged; the intermediate vector copy is removed. |
| Zero initialization | Three explicit whole-buffer zeroing passes are removed. | Each fresh byte buffer was already value-initialized to zero by its constructor or resize, including padding bytes. |

The isolated constant-payload destruction test first ran against build 538, before the owning-table
change. It was the only failing test: 691 passed and one failed. Like build 536, build 538 was an
intermediate functional baseline, not a retained implementation or a timing baseline. The shared
test helper checks live blocks in a dedicated mimalloc heap, without measuring process memory.

Additional tests retain constant references across 4,096 insertions and verify canonical hits,
stable addresses, payload contents, and diagnostic pointers. Repeated string inputs cover alias
normalization and nullable types. Alias inputs can miss the initial lookup and then normalize to
an existing string entry; this path returns that existing reference and destroys the rejected copy.
The stored value and normalized type remain unchanged.

Symbol-order tests compare explicit expected results and the original textual-key algorithm for
same-file views, missing files, token-width boundaries, invalid tokens, stable equal-key symbols,
and multi-file path-prefix cases.

Both build-539 compiler configurations built successfully. The same constant-payload destruction
test that failed on build 538 now passes. The C++ selection still excludes the 28 filesystem tests.

| Build-539 complete suite | Result | Evidence |
| --- | --- | --- |
| C++ | 694 passed | [Log](cpp-539.log) |
| Semantic analysis | 278 valid inputs and 293 expected-error inputs verified | [Log](sema-539.log) |
| JIT | 1,402 passed | [Log](jit-539.log) |
| Native, program configuration `devmode` | 3,137 passed; generated executable passed | [Log](native-devmode-539.log) |
| Native, program configuration `release` | 3,137 passed; generated executable passed | [Log](native-release-539.log) |

Focused JIT checks passed for aggregate numeric arrays (1), compiler globals (1), non-null values
(3), large-struct binding (2), constant slices (6), and aggregate constant assignment (4). Native
checks passed for temporary receiver lifetime (2), caller-expression arguments (1), automatic macro
receivers (1), indexed macro receivers (1), deferred re-emission (2), constant slices (6), array
casts (2), array literals (14), globals (1), struct defaults (6), and null/default initialization (10).
The initial `array.swg` filter also selected an example without its allocator helper; it was
replaced with the self-contained `casts\array.swg` and `literals\array.swg` filters. No compiler
source change was needed for that selection error.

The Release compiler passed [large-struct binding](release-compiler-large-struct-539.log) (2 JIT
tests), [constant slices](release-compiler-const-slice-539.log) (6 native tests),
[constant-address storage](release-compiler-rdata-539.log) (1 native test), and
[aggregate numeric arrays](release-compiler-array-539.log) (1 JIT test).
The workspace consumer was rebuilt and executed by both the
[DevMode compiler](workspace-consumer-539.log) and the
[Release compiler](release-compiler-workspace-consumer-539.log), with the same forced-rebuild
command as build 537. Both runs rebuilt three standard dependencies and six local modules and
passed initialization and destruction assertions across static libraries and a DLL.

## Additional reduction in build 540

Constant-count initialization of simple elements now emits one contiguous zero-fill operation
instead of repeating type checks, address generation, and initialization for every element.
The existing memory emitter chooses a bounded unroll or runtime loop for the complete block.
Structs, nested arrays, enums, explicit-initialization requirements, zero/one counts, and sizes
beyond the 32-bit memory-emitter limit keep their previous handling. No micro pass is changed.

The new native fixture checks counts 0, 1, and 1,024 for `s32`, 1,023 bytes starting at an offset
of one, nullable-pointer aliases, and the unoptimized memory-emitter path. Sentinels before and
after each initialized range must remain unchanged. The first three cases also passed on build
539 before the lowering change; this was a functional comparison, not a timing baseline.

A new C++ constant-interning regression synchronizes two threads across 128 common aggregate
insertions and 256 distinct ones. It verifies canonical references, diagnostic pointers, stable
addresses, independent owned copies, and values after the input vectors have been destroyed.

Both build-540 compiler configurations built successfully. The same 28 filesystem C++ tests remain
excluded. The unoptimized helper explicitly carries `NoInline` as well as `Optimize(false)` so
automatic inlining cannot remove the intended configuration boundary.

| Build-540 validation | Result | Evidence |
| --- | --- | --- |
| C++ | 695 passed, including concurrent constant interning | [Log](cpp-540.log) |
| JIT | 1,402 passed | [Log](jit-540.log) |
| Native, program configuration `devmode` | 3,141 passed; generated executable passed | [Log](native-devmode-540.log) |
| Native, program configuration `release` | 3,141 passed; generated executable passed | [Log](native-release-540.log) |
| Bulk-default fixture, `devmode` | 4 passed; generated executable passed | [Log](native-bulk-default-540.log) |
| Bulk-default fixture, `release` | 4 passed; generated executable passed | [Log](native-bulk-default-release-540.log) |
| Existing lifecycle fixture, `devmode` | 42 passed; generated executable passed | [Log](native-lifecycle-540.log) |
| Existing lifecycle fixture, `release` | 42 passed; generated executable passed | [Log](native-lifecycle-release-540.log) |
| Release compiler, bulk-default fixture | 4 passed; generated executable passed | [Log](release-compiler-bulk-default-540.log) |

The lifecycle filter is `intrinsics\lifecycle.swg`: the shorter filename also selected a
workspace-dependent root fixture and initially failed for missing helpers. Correcting the filter
required no compiler change. The first three bulk-default cases have a separate
[pre-change functional log](native-bulk-default-539-baseline.log).
Semantic analysis and the forced workspace consumer retain their build-539 evidence; build 540
changes only the described lowering path and adds the concurrent C++ regression.

## Final validation strengthening in build 542

The concurrent type-interning test now uses three disjoint families of 1,024 types, rather than
256. Their 3,072 distinct arena objects exceed the combined capacity of one default 16 KiB page
in each of the eight shards. This guarantees physical page growth, independently of hash
distribution, while both threads retain references to earlier entries. The final checks cover
canonical identity, payload contents, stable addresses, and diagnostic references after growth.

Both compiler configurations built successfully, and [all 695 C++ tests passed](cpp-542.log),
with the same 28 filesystem tests excluded. This final change only enlarges the test and updates
the compiler cache identity. The production algorithms are unchanged from build 540, whose JIT
and native results remain the final language-suite evidence above.

## Additional reductions in build 543

String interning accepts a borrowed `string_view` for lookup and copies directly into its final
NUL-terminated segment storage on a miss. The map still owns independent string keys: restoring
mutable segment bytes must not change their identity. This removes implicit input conversion,
the temporary terminated-string buffer, and explicit name copies in type metadata generation.
Empty views, embedded NUL bytes, stable storage, relocation layout, and locking are preserved.

Repeated alias-string constants now check their normalized key under the original stripe's
exclusive lock before allocating a new arena object. The original input still selects the shard
and stripe, and nullable string types retain their type. The repeated-input regression now also
requires the segment extent to remain unchanged on canonical hits.

Local declarations first compare the last registered symbol, or the exact suffix for a group.
The usual register/ensure sequence consequently avoids rescanning all previously declared locals.
Older-symbol lookups and reentry keep the existing complete search, including redirected scopes.
Two code-generation traversals append children directly to their DFS stack, removing an
intermediate child vector and copy at each visited node while preserving valid-node LIFO order.
No micro pass is changed.

Two new C++ tests cover destroyed or modified input buffers, non-terminated subviews, embedded
NULs, null-data empty views, page and oversized-block growth, stable interned references,
relocations, and lookup keys independent of restored payload bytes.
Both build-543 compiler configurations built successfully. All tool-driven validations were
serialized. The same 28 filesystem C++ tests remain excluded. No timing comparison was performed.

| Build-543 complete suite | Result | Evidence |
| --- | --- | --- |
| C++ | 697 passed | [Log](cpp-543.log) |
| Semantic analysis | 278 valid inputs and 293 expected-error inputs verified | [Log](sema-543.log) |
| JIT | 1,402 passed | [Log](jit-543.log) |
| Native, program configuration `devmode` | 3,141 passed; generated executable passed | [Log](native-devmode-543.log) |
| Native, program configuration `release` | 3,141 passed; generated executable passed | [Log](native-release-543.log) |

Focused JIT checks passed for [attribute parameter names](jit-typeinfo_attribute_param-543.log)
(1), [aggregate metadata](jit-typeinfo_aggregate-543.log) (5),
[generic function metadata](jit-typeinfo_function_generics-543.log) (1),
[inline binding usage](jit-binding_usage_summary-543.log) (3), and
[binding visitor growth](jit-binding_visit_growth-543.log) (1).
Native checks passed for [string literals](native-literals-string-543.log) (19),
[string variants](native-string_variants-543.log) (13),
[deferred re-emission](native-defer_reemission-543.log) (2),
[defer control flow](native-compiler-defer-543.log) (5),
[cross-file injected macro payloads](native-code-payload-543.log) (1),
[struct field metadata](native-typeinfo_struct_fields-543.log) (6), and
[function metadata](native-typeinfo_function-543.log) (1).
The initial `code_payload_macro.swg` selection was only a provider and executed zero tests;
it is not counted as functional evidence. The corrected `code_payload` filter includes the
provider, container, and executable caller test.

The Release compiler passed native checks for
[attribute parameters](release-compiler-typeinfo_attribute_param-543.log) (1),
[generic functions](release-compiler-typeinfo_function_generics-543.log) (1),
[string literals](release-compiler-literals-string-543.log) (19), and
[deferred re-emission](release-compiler-defer_reemission-543.log) (2).
The forced workspace consumer rebuild passed with both the
[DevMode compiler](workspace-consumer-543.log) and the
[Release compiler](release-compiler-workspace-consumer-543.log). Each rebuilt three standard
dependencies and six local modules, executed the main entry point, and passed the cross-module
initialization and destruction assertions.

## Additional reductions in build 544

Aggregate destructuring keeps a local layout cursor instead of recalculating offsets from the
first field for every access. Increasing field indices, including skipped fields, visit each
layout prefix once; a backwards named access restarts the cursor. Each cursor belongs to one
traversal of one type, and assignment resets it before dropping unbound fields. Struct-symbol
field offsets retain their existing direct lookup. Three new native tests cover padding,
zero-sized and ignored fields, declarations, assignments, and reversed named access.

Function-candidate probing borrows the published parameter list instead of copying it for every
candidate. Aggregate-array generic deduction skips consecutive equal raw types only for a direct
identifier binding. Nested dimensions and composite patterns still run in full: their partial
transactional deductions are not generally idempotent. Three native tests cover 32 equal element
types, unsized-to-sized refinement, alternating types, and identical multidimensional rows.
Both new native fixtures passed on build 543 before compiling these production changes.

Symbol-list payload flags consume the original pointer span instead of constructing a temporary
const-pointer vector under the store lock. Narrowing invalidation compacts surviving facts in
place while preserving their order, and skips empty input. Two C++ tests cover mutable/const
symbol inputs, aliases, empty and large lists, copied storage, flag preservation, empty/no-match
kills, same-name symbols, deep paths, and newest-proof/kill precedence.

Generated API attribute normalization compacts disjoint shrinking edits in one pass. Each retained
byte moves at most once rather than once per subsequent edit; no extra output buffer is allocated.
The sorting and lexer logic are unchanged. Before rebuilding, 42 generated Swag source hashes
were captured for comparison after a forced workspace rebuild.

Build 544 uses the DevMode compiler: these changes add no shared lifetime, scheduling, or
configuration-specific compiler path. Its build and all selected validations passed.

| Build-544 validation | Result | Evidence |
| --- | --- | --- |
| C++ | 699 passed; 28 filesystem tests excluded | [Log](cpp-544.log) |
| Semantic analysis | 278 valid and 293 expected-error inputs verified | [Log](sema-544.log) |
| JIT | 1,402 passed | [Log](jit-544.log) |
| Native, program configuration `devmode` | 3,147 passed; generated executable passed | [Log](native-devmode-544.log) |
| Native, program configuration `release` | 3,147 passed; generated executable passed | [Log](native-release-544.log) |
| Destructuring layout | 3 passed | [Log](native-destructuring_layout-544.log) |
| Generic element-type runs | 3 passed | [Log](native-aggregate_type_runs-544.log) |
| Existing destructuring assignments | 12 passed | [Log](native-assign_destruct-544.log) |
| Existing temporary destruction | 17 passed | [Log](native-temporary_drop-544.log) |
| Forced workspace consumer | Three standard dependencies and six local modules rebuilt; main passed | [Log](workspace-consumer-544.log) |

The initial six-worker source-hash comparison was not identical. Repeating build 543 alone also
changed `BorrowSummary` annotations, generated source numbering, and foreign-library ordering.
The varying borrow summaries are already tracked in
[compiler.core.032](../../../../backlog/compiler.core.md#compilercore032--repeated-module-builds-publish-different-borrow-summaries).
This prevents treating the parallel byte comparison as a regression oracle. Separate forced
single-worker workspace rebuilds with Release 543 and DevMode 544 produced exactly the same set
of 40 generated Swag source files, with every SHA256 hash identical
([comparison](api-source-comparison-544.log)). The normal six-worker functional validations above
remain the evidence for parallel compilation; no timing comparison was performed.
