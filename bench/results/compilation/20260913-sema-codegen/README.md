# Semantic analysis and code generation work reductions, 2026-09-13

This change removes repeated work outside the micro passes. Functional validation targets
compiler builds 532 through 535 on `1cb02fdaa` plus the changes below. Work is isolated on
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
