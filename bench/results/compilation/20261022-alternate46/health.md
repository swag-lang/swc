# Compiler health batches, 2026-10-22

This prompt-6 campaign starts at `89bc0335af` in the external `prompt6` worktree
of `alternate46-20261022-0740`, alternating with prompt 4 until 12:00 Europe/Paris.
`SWC_BUILD_NUM` stays unchanged. Temporary files and caches are isolated outside
the checkouts. Every build/test has fresh machine-load admission and a six-worker cap.

| Retained change | Equivalence and coverage | Validation |
| --- | --- | --- |
| Share library-backend classification | `Runtime::backendKindIsLibrary` retains the exact StaticLibrary/SharedLibrary switch, including false for other values. It replaces two identical private predicates and the equivalent early-return switch in runtime-hook construction. Call sites read the same configuration once; no object layout, configuration, artifact format, API export policy or runtime hook changes. The header-side constexpr body preserves inlining visibility. | DevMode and Release builds; 1,544 default C++ tests; `consumer_exe` passes its seven native tests with each compiler in the `devmode` program configuration, including linked static/shared imports and generated APIs. |
| Share scalar ABI width conversion | One inline `ABICall::valueBits` replaces two private twins and five fallback expressions. Zero retains its 64-bit default; valid widths retain the same enum values. The existing nonzero-width assertion is shared, deliberately adding that invariant to the two return paths that previously lacked it. Existing assertion sites move to the helper. Integer/float normalization, register selection, evaluation and emitted operations are unchanged for valid input. | DevMode and Release builds; 1,544 default C++ tests, including narrow integer and FFI coverage; the independent-argument-bank native input passes its test and compile-time assertions with both compilers in `devmode`. |
| Share array-count failure construction | Dimension-count and excess-value failures now pass their diagnostic ID to one helper, preserving the failure call and the order/types/values of its count and value arguments. The unused dimension-index parameter is removed from the separate mismatch helper; its index still selects the same dimensions at the caller. Struct-count failures retain their distinct 32-bit argument contract and additional literal-kind argument. | Incremental DevMode build; five array-conversion error inputs pass expected-diagnostic verification (33 inputs including 28 runtime sources). The ordinary selection contains only runtime and is not counted as array-case coverage. No runtime test bodies execute in these semantic checks. |
| Keep constant-service headers dependent on their declarations | `ConstantExtract.h` needs reference handles, not an AST node definition. `ConstantLower.h` needs only a forward declaration of `DataSegment`. Remove those service includes and add the concrete data-segment include directly in eight implementations that use its types or operations. No declaration, expression, layout, ownership or generated-code policy changes. Both owning implementations include their own header first after the PCH, covering header completeness in the project's standard-header context. | DevMode and Release builds. This include-only batch needs no runtime test beyond its compilation boundary. |
| Share directory-creation families | An inline filesystem helper preserves the identical create/error-normalize/report sequence for documentation, new-project creation and API export. The API-export wrapper keeps its empty-path guard. Two private native artifact methods collapse into one, retaining their separate raw-system-message/backend diagnostic policy. Workspace synchronization retains its additional file-user reporting, and best-effort cache creation keeps its no-diagnostic contract. Directory paths, call order, diagnostic IDs/arguments and exception behavior are unchanged. | DevMode and Release builds; all 1,611 C++ tests with `--dev-full` pass, including project-creation and documentation filesystem checks. This ten-batch milestone includes the concurrent call-copy and root-product integrations present in its source base, but precedes the next prompt-4 parameter-normalization batch. |
| Share SSA known-value propagation setup | Branch simplification and constant folding used identical wrappers around the same fixed-point engine and known-value types. One header-side template retains their five arguments and context construction; its compile-time callback preserves each pass's distinct inference routine without adding dispatch. Both pass entry points retain their instruction counts, call counts, final instruction offsets and stack reservations; the outlined branch wrapper also retains its 17 instructions, two calls and 0x58-byte stack. Differences in instruction text are callback/helper symbols and assertion source-line numbers. | DevMode and Release builds; all 1,549 default C++ tests pass, including branch simplification and constant folding. |
| Share the inline caller-scope predicate | Two private predicates asked whether a nullable inline payload refers to a macro/mixin source function. One inline `SemaInline::usesCallerScope` retains the same payload guard, source-function guard and attribute query in the same order. All four calls move directly, including the conditionally evaluated frame lookup. Existing nullable-payload utilities already live in this header; no data member or dependency is added. The three containing DevMode functions retain their instruction/call counts, final offsets and stack reservations. | DevMode and Release builds; two explicit permanent JIT inputs pass 14 tests, covering macro closure capture and nested local functions. |
| Share relocation-target insertion | Two payload producers used the same function-symbol/data-offset dispatch. A header-side `DataSegment::addRelocation` overload retains that dispatch, target shard/offset/symbol fields and unresolved-function flag. Callers retain their loops and absolute-offset arithmetic. Each insertion still takes the same lock, appends the same record and updates the same index/version; no descriptor layout or relocation format changes. The aggregate materializer retains 337 instructions, 30 calls, its final offset and 0x138-byte stack; global allocation retains its 57 calls and 0x1B0-byte stack, with one fewer instruction. | DevMode and Release builds; two permanent union-constant/global-function-pointer inputs pass eight native tests in `devmode`. |
| Centralize standard includes and make source-range dependencies direct | Remove 18 standard-library includes from 14 project headers. Their translation units already receive those declarations through the required PCH; add the sole missing central declaration, `<cstring>`, there. The early CPU guard and vendored mimalloc translation unit do not consume the changed headers. `TypeInfo.h` declares no source-range type, so remove that dependency and include its declaration directly in four headers that actually use it. No declarations, expressions, type layouts or runtime behavior change. | Complete DevMode and Release builds, including both PCH rebuilds. These dependency-only edits are validated at their compilation boundary. |

The default-argument constant selection is now shared by semantic execution
and call code generation in `SemaCallArgument::tryResolveDefaultConstant`.
It initializes the same invalid reference, selects the same explicit constant,
and leaves caller locations to their original execution context. Both private
wrappers keep their source-range, function-context and failure propagation.
The two DevMode wrappers and their three containing callers retain their
instruction/call counts, final offsets and stack reservations. The linked
DevMode executable remains 16,622,080 bytes. DevMode and Release builds pass;
three permanent caller-location/default-argument inputs pass 18 tests and
their compile-time assertions, including `#run` and generic allocator calls.

Two template/callback trials were discarded: they redistributed work into
callers and enlarged stack frames. The retained plain inline selector shares
the duplicated switch without introducing a callback or template instance.

The raw-string and unescaped-string arms now share their identical constant
construction. The raw guard still short-circuits the escaped-token query, and
multiline normalization and escape decoding retain their original order.
Square-root and logarithm domain checks likewise share the identical compare
and conditional-jump emission; their predicates retain the same order and
short-circuiting, and the asin/acos arm is unchanged. These edits select the
same Micro operations and descriptors for every input. The literal function
keeps its 0x1E0-byte stack; the math helper keeps its direct-call count and
reduces its stack from 0x78 to 0x70 bytes. DevMode builds; both permanent
string inputs pass semantic checking and compile-time assertions, without
executing runtime tests. The permanent math-safety input passes 11 guarded
tests and its expected-diagnostic verification in `devmode`.

Commands, from this worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe unittest --num-cores 6
bin/swc.dm.exe unittest --dev-full --num-cores 6
bin/swc.dm.exe test --workspace bin/unittests/workspace --workspace-module consumer_exe --no-test-jit --num-cores 6 --rebuild
bin/swc.exe test --workspace bin/unittests/workspace --workspace-module consumer_exe --no-test-jit --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter call_independent_arg_banks --num-cores 6 --rebuild
bin/swc.exe --num-cores 6 tools/unittests.swgs native --file-filter call_independent_arg_banks --num-cores 6 --rebuild
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm sema --file-filter sema_err_array_cast_ --num-cores 6 --rebuild
```

The initial consumer command omitted `--no-test-jit` and failed while resolving
static-library foreign functions for JIT execution. The official workspace suite
explicitly selects native-only execution for this fixture; the corrected commands
above pass without changing compiler behavior or weakening the fixture.

Default C++ tests omit filesystem tests requiring `--dev-full`. Both consumer
results use separate temporary/cache roots. Evidence belongs to each tested
source batch; a conflict-free integration does not certify subsequent foreign
changes. This is a bounded set of mechanical cleanups, not whole-tree coverage.

The two `makeMaterializedConstantValue` helpers are not interchangeable copies:
their storage-kind dispatch differs for string/slice and fallback values. One
uses generic constant construction where the other selects borrowed struct
storage. Choosing a common representation contract is design work; this
mechanical pass leaves both dispatch policies unchanged.

The first SSA factoring trials passed the callback at runtime and enlarged the
DevMode stack frames despite adding no call sites. They were discarded. The
retained compile-time callback reproduces the original allocation and call shape.

Repeated `--file-filter` values intersect; the first multi-filter selections
executed zero tests and are not coverage. The scope check uses two explicit
`-f` inputs, `--no-output`, the JIT module namespace and external output/work paths.

Relocation factoring first shared the whole loop through a span, then a vector
reference; both trials added instructions to the materializer. A relative-offset
per-record helper still added one move. The retained overload accepts the
absolute destination already calculated by the caller and adds no operations.
An extra union-function-pointer probe used unsupported constant function
addresses and failed semantic checking; it was excluded from validation coverage.
