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

Prompt-6 results are recorded in [health.md](health.md).

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
