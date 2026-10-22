# Alternating compilation speed and compiler health, 2026-10-22

This time-bounded session starts at `89bc0335af` and alternates prompts 4 and 6
until 12:00 Europe/Paris. Each campaign has a separate external worktree under
`%LOCALAPPDATA%/swc-agent-builds/alternate46-20261022-0740`, on
`perf/prompt4-alternate-20261022-0740` and
`quality/prompt6-alternate-20261022-0740` respectively. Builds and tests use fresh
machine-load admission, at most six workers and checkout-local compilers.
`SWC_BUILD_NUM` is unchanged. Temporary/cache roots and raw logs stay outside
the checkouts. No timing campaign or profiler runs; speed targets remain unverified.

| Prompt | Retained change | Equivalence and structural evidence | Validation |
| --- | --- | --- | --- |
| 4 | Read block-flow children directly from their AST spans | Five compound node types inherit the same span-only collector. Function-exit analysis visits the same references in order and short-circuits at the same first exit. Block-exit analysis reads only the final reference. Missing/empty spans still return false. The temporary child vector, its reference copies, possible allocation and destruction disappear; persistent storage is unchanged. | DevMode build; complete semantic selections: 297 ordinary and 350 expected-diagnostic inputs, including runtime, with expectations verified. These semantic stages execute no runtime test bodies. |
| 4 | Reuse the reflected field CRC for its using-field descriptor | Both records describe the same stable identifier bytes. Reusing the already written CRC removes a second CRC-32 byte/bit walk, without adding storage or allocations. The compiler's `initStruct` loses one CRC call (four to three static call sites; 123 to 122 calls overall), keeps its 0xA48-byte stack reservation, and grows by 47 code bytes. No elapsed-time or peak-memory claim is made. | DevMode build; `dynamic_using_cycle` passes three native tests and its compile-time assertions, exercising reflected using-field graphs. |
| 4 | Allocate walk-cache indices without clearing unread slots | Every index is assigned before its nonzero occupancy key can be queried, and growth reads old indices only for occupied keys. Initial and grown index arrays lose their zero pass. Key-array clearing, capacity, growth, entry addresses and query/version behavior are unchanged. The index array retains four bytes per slot; its unique pointer removes the unused vector size/capacity fields. | DevMode build; all 1,545 default C++ tests pass, including a new 4,096-root walk on a fresh worker, growth, relocation-version refresh and a subsequent query excluding the relocated root. |
| 4, repair | Adapt native fixtures to non-null memory destinations | Three native inputs and the runtime's private error-transport test helper still passed nullable destinations to the now non-null `Swag.memcpy` API. Required buffers are narrowed before copying; the zero-size nullable-wrapper path and every test assertion remain. Error-message copies retain one non-null byte pointer for both copy and string construction. No compiler/API contract changes. | Stable formatting; the three inputs plus their allocator helper pass ten tests as a standalone selection; the complete native suite passes 3,924 tests and the expected idle/pending/hardware recovery probes, with outer exit zero. |
| 4 | Stop auto-inline body measurement at its first blocker | The initial shape is unblocked, and the recursive caller now stops its sibling loop immediately after a child sets the monotonic blocked flag. Remove the corresponding callee-entry guard. The same prefix sets call/static-storage/non-null flags; later siblings previously returned at that guard without changing anything. This removes their loop iterations and recursive calls, with no extra storage or allocation. The DevMode helper keeps its 0x160-byte stack reservation and grows by 79 code bytes, largely through inlined cleanup; this is not a quantitative speed or memory claim. | Incremental DevMode build; all 1,546 default C++ tests pass, including parse-time auto-inline classification and actual expansion cases. |
| 4 | Reuse normalized code-block parameter metadata | The existing `unwrapAliasEnumTypeOrSelf` follows the same alias/enum chain and retains the original type when no underlying type exists. Borrow its resulting metadata directly instead of returning a type handle, checking its fallback and looking that handle up again. Invalid parameter handles still return false before normalization. No storage, allocation or parameter-binding policy changes. The containing helper keeps the same static call count, shrinks its stack reservation from 0x528 to 0x518 bytes and grows by eight code bytes. | Incremental DevMode build; the trailing-code-block error-management JIT input passes its test, covering expect/try/catch calls and block binding. |
| 4 | Reuse the start coordinates already obtained for AST ranges | Boundary traversal has already calculated the start token's source, line and UTF-8/tab-aware column. Retain those fields and replace only its span length instead of repeating the final line-table search and column decoding. The original byte-bound checks and invalid-token fallback remain, with no added persistent storage or allocations. The explicit-view overload retains its 0xD0-byte stack; its final instruction offset grows by 55 bytes, and the forwarding overload is no longer inlined into a second copy. | DevMode build; all 1,551 default C++ tests pass, including 32 combinations of UTF-8, tab widths, line offsets, absent line tables and multiline boundaries, plus invalid/EOF/truncated-token fallbacks. Two permanent binary-operand/overload error inputs pass semantic verification; their verbose labels, underlines and candidate notes were inspected. |
| 4 | Read anonymous aggregate-pattern fields from their AST span | The parser always gives anonymous struct/union declarations an `AggregateBody`, whose collector copies only its child span. Walk those immutable chunks directly, retaining invalid-body/span guards, reservation count, declaration order and descriptor construction. The chunk iterator already carries the total count, so reservation does not reread the span header. Remove the intermediate reference vector, its initialization/copies and possible allocation/destruction. The anonymous collection helper's stack shrinks from 0x160 to 0x90 bytes; its code grows by 58 bytes. Both containing deduction functions and the named-field collector keep their previous code sizes, call counts and stack reservations. | Incremental DevMode build; the permanent native `functions_defaults_context` input passes four tests, covering anonymous fields, named aggregate defaults and inferred types. |
| 4 | Reuse the normalized lifecycle-intrinsic operand | The semantic node view already owns the operand type metadata. Normalize it directly instead of looking its handle up before and after alias/enum unwrapping; retain the result for the later addressability check rather than repeating that traversal. The early pointer return already proves the removed pointer guard. Null types, symbol checks, lvalue validation and count casts retain their order and outcomes. The containing DevMode helper keeps its 0x1A0-byte stack and 24 direct call sites while shrinking by 15 code bytes; its former nested lookup helper and second normalization disappear. | Incremental DevMode build; the permanent intrinsic lifecycle input passes 42 native tests, including strict aliases, enums, pointer/count forms and lifecycle hooks. |
| 4 | Reuse the string insertion key hash | String relocation into stable storage preserves its kind, type and bytes, which are exactly its hash inputs. Preserve the original shard selection, reuse the incoming hash when the type is retained, and retain the already computed normalized hash when an alias changes the stored type. Publication loses the final byte-hash traversal; stripe selection, locking, canonicalization and interning policy are unchanged. Reusing the existing hash variable avoids a longer-lived extra value. The DevMode insertion helper retains its 0x138-byte stack, drops from 31 to 29 direct calls and shrinks by seven code bytes. | Incremental DevMode build; all 1,551 default C++ tests pass. The existing string-normalization test now covers five payloads across ordinary, nullable and alias types: empty, ordinary, embedded NUL, UTF-8 and a 4,097-byte value, retaining its repeated identity, storage-extent and debug-reference checks. |

Prompt-6 results are recorded in [health.md](health.md).

The trailing-code-block sibling search now borrows the four accepted compound
nodes' immutable child spans. It finds the call and following eligible sibling
across chunks without constructing, filling or destroying a temporary vector.
Invalid references, duplicate call references, the first blocking sibling and
single-statement wrapper ascent retain their previous behavior. The containing
DevMode helper drops from 299 instructions and 16 calls to 263 instructions and
14 calls; its stack reservation falls from 0x180 to 0xD0 bytes. Its caller keeps
the same instruction/call counts and 0xA0-byte stack. These comparisons include
local assembler labels; an audit of earlier comparisons found one incomplete
global-allocation call count, corrected to 57 in the health report.

The DevMode build and all 1,552 default C++ tests pass. The new in-memory
regression executes a trailing macro block after more than one page of statement
references and verifies that its parsed body actually spans multiple chunks.
Its initial postcondition incorrectly expected a synthesized `FunctionBody`
instead of the parser's `EmbeddedBlock`; correcting that test assumption retains
the multiple-chunk requirement. The permanent error-management trailing-block
input also passes its JIT test, including wrapper ascent and block binding.

Commands, from the corresponding campaign worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe unittest --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm sema --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter dynamic_using_cycle --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm jit --file-filter code_trailing_block_error_management --num-cores 6 --rebuild
bin/swc.dm.exe test -f bin/unittests/errors/sema/sema_err_binary_operand_type.swg -f bin/unittests/errors/sema/sema_err_no_overload_match.swg --sema-only --verbose-verify --num-cores 6 --rebuild
```

Validation evidence belongs to the source batch tested; a conflict-free merge
alone does not certify subsequent concurrent changes on `master`.

The vector-intrinsic argument-view trial was discarded before validation: the
borrowed indexed view removes copying but adds out-of-line indexing calls, so
its aggregate work reduction was not established. No trial code is retained.

## Five-batch correctness milestone

Compiler source `e67975cde4` passes all 1,609 C++ tests with `--dev-full`,
including filesystem coverage. Its first complete native attempt identifies
three stale nullable-destination calls; the focused repair exposes and fixes
the same call in the runtime's private transport test helper. With those four
source repairs, the same compiler passes all 3,924 native tests. The recovery
probes deliberately fail their child processes; the enclosing tool exits zero.
These results precede concurrent prompt-2 call-copy scheduling changes and the
later prompt-6 array-diagnostic cleanup. They are not a full-master rerun.

Additional commands:

```text
bin/swc.dm.exe unittest --dev-full --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --num-cores 6 --rebuild
bin/swc.dm.exe test --artifact-kind executable --module-namespace Native -f bin/unittests/native/inline/nullable_parameter_widening.swg -f bin/unittests/native/compiler/ast_implicit_string_return.swg -f bin/unittests/native/runtime/error_storage.swg -f bin/unittests/native/runtime/default_allocator_helpers.swg --out-dir <external>/native-contract-out --work-dir <external>/native-contract-work --num-cores 6 --rebuild
```

`<external>` is the session's external `alternate46-20261022-0740` directory.
The four repaired Swag files were formatted twice with the checkout-local
compiler; final hashes were stable. The focused allocator helper is included
explicitly because a filename-only filter would otherwise remove it.

The initial combined named/anonymous field-walk trial changed inlining and
enlarged the recursive named deduction frame by 96 bytes. It was discarded;
only the anonymous walk with unchanged parent frames is retained. Its native
validation uses one filename filter: repeated filters intersect and the first
multi-filter trial selected no owned tests.

## Fifteen-batch correctness milestone

The combined source at `0469edb6e7` passes all 1,615 C++ tests with
`--dev-full` and all 3,927 native tests, followed by the expected idle,
pending-work and hardware-fault recovery probes. Their enclosing tool exits
zero. The same DevMode compiler drives both checks, with a fresh isolated cache.
This milestone includes both campaigns through the anonymous aggregate field
walk and precedes the lifecycle-intrinsic operand change recorded above.

A direct inline-constant span query was discarded: its stack iterator enlarged
the helper frame by 64 bytes. The first string-hash trial kept an extra live
hash and enlarged its frame by 16 bytes; the retained version reuses the input
hash variable after preserving the original shard selection and keeps the frame.

## Twenty-batch correctness milestone

The combined source at `31080463a5` passes all 1,618 C++ tests with
`--dev-full` and all 1,539 JIT tests. This milestone includes both campaigns
through standard-header cleanup and trailing-block sibling traversal, together
with the prompt-2 whole-vector lane differences already integrated on `master`.
The DevMode compiler is built from that combined source; both checks use a fresh
isolated cache. Subsequent batches have their own focused validation.

## Reuse reference-comparison operand metadata

`structReferenceForEquality` already checks the operand's cached type pointer.
Dereference it instead of fetching its handle and resolving it through the type
manager again. View construction and successful conversions keep the pointer
and handle paired, including narrowing; the opposite operand is already read
through the same cached metadata path. All guards, normalization, conversion
order and results remain. No storage or allocation changes. The DevMode helper
drops from 104 instructions and 14 calls to 96 instructions and 12 calls, keeps
its 0x70-byte stack, and shortens its final instruction offset by 31 bytes.
Its promotion and relational-node callers retain their instruction/call counts,
final offsets and stack reservations. The DevMode build and both permanent
native reference/comparison inputs pass all 37 tests and compile-time assertions.

## Read only the declared equality parameter

`declaredEqualityTargetsOwner` inspects only the first declared parameter.
The parser creates a `FunctionParamList`, and cloning preserves that node kind;
its collector copies only its child span. Borrow its first chunk instead of
copying the whole list into a temporary vector. Keep the same valid-span and
empty-list behavior, attribute unwrapping, type walk and owner-name comparison.
The unused tail is not traversed; vector initialization, copies and possible
allocation/destruction disappear. Persistent storage is unchanged. DevMode's
helper stack falls from 0x190 to 0xC0 bytes. Its local inlined access/validation
code grows from 284 instructions and 29 calls to 307 instructions and 30 calls,
with the called collector/copy/destructor paths removed. Its three containing
equality helpers retain their instruction/call counts, offsets and stack
reservations. The DevMode build and permanent generated-equality input pass
15 tests, including explicit self overloads, additive other-type overloads,
nested/anonymous fields, ignored fields and compile-time assertions.
