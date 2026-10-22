# Compiler health batches, 2026-10-22

This prompt-6 campaign starts at `89bc0335af` in the external `prompt6` worktree
of `alternate46-20261022-0740`, alternating with prompt 4 until 12:00 Europe/Paris.
`SWC_BUILD_NUM` stays unchanged. Temporary files and caches are isolated outside
the checkouts. Every build/test has fresh machine-load admission and a six-worker cap.

| Retained change | Equivalence and coverage | Validation |
| --- | --- | --- |
| Share library-backend classification | `Runtime::backendKindIsLibrary` retains the exact StaticLibrary/SharedLibrary switch, including false for other values. It replaces two identical private predicates and the equivalent early-return switch in runtime-hook construction. Call sites read the same configuration once; no object layout, configuration, artifact format, API export policy or runtime hook changes. The header-side constexpr body preserves inlining visibility. | DevMode and Release builds; 1,544 default C++ tests; `consumer_exe` passes its seven native tests with each compiler in the `devmode` program configuration, including linked static/shared imports and generated APIs. |

Commands, from this worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=Release /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe unittest --num-cores 6
bin/swc.dm.exe test --workspace bin/unittests/workspace --workspace-module consumer_exe --no-test-jit --num-cores 6 --rebuild
bin/swc.exe test --workspace bin/unittests/workspace --workspace-module consumer_exe --no-test-jit --num-cores 6 --rebuild
```

The initial consumer command omitted `--no-test-jit` and failed while resolving
static-library foreign functions for JIT execution. The official workspace suite
explicitly selects native-only execution for this fixture; the corrected commands
above pass without changing compiler behavior or weakening the fixture.

Default C++ tests omit filesystem tests requiring `--dev-full`. Both consumer
results use separate temporary/cache roots. Evidence belongs to each tested
source batch; a conflict-free integration does not certify subsequent foreign
changes. This is a bounded set of mechanical cleanups, not whole-tree coverage.
