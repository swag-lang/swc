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

Commands, from this worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe unittest --num-cores 6
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
