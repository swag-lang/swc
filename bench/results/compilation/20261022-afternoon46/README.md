# Alternating compiler campaigns, 2026-10-22 afternoon

This bounded session starts at `74ba1680d3` and alternates prompts 4 and 6
until 18:00 Europe/Paris. The separate external worktrees are under
`%LOCALAPPDATA%/swc-agent-builds/alternate46-20261022-1515`, on
`perf/prompt4-alternate-20261022-1515` and
`quality/prompt6-alternate-20261022-1515`. Each build/test has fresh machine-load
admission and at most six workers. Temporary files and caches stay outside
the checkouts. `SWC_BUILD_NUM` is unchanged. No timing, profiler or peak-memory
campaign runs; compilation-speed targets remain unverified.

| Batch | Change and equivalence | Validation |
| --- | --- | --- |
| 4.1 | Resolve structure-operator owners from the operand's existing metadata. Reference/non-null pointer payload selection, alias-only normalization, invalid-payload fallback and enum preservation remain. Remove the ordinary type-table lookup and the final lookup after normalization; no persistent storage or allocation is added. The DevMode helper has 65 instructions and eight calls instead of 130 and fourteen, and reserves 0x50 rather than 0x80 stack bytes. These are code-shape observations, not timing measurements. | DevMode build; all 248 native spec-operator tests pass in `devmode`. |
| 4.2 | Reuse normalized metadata for overloaded slice bounds and unary operators. The existing alias-only metadata API preserves enum wrappers, reference handling and invalid-payload fallback. Bounds lose the generic expansion call for ordinary types and the final type-table lookup; unary resolution loses its redundant initial/final lookups. No storage or allocation is added. The bounds helper changes from 356 instructions/42 calls/0x128 stack bytes to 342/39/0x108; unary resolution changes from 313/31/0x2C8 to 239/24/0x290. | Incremental DevMode build; all 248 native spec-operator tests pass in `devmode`, including slice and unary operators. |

Commands, from the corresponding campaign worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter '\specops\' --num-cores 6 --rebuild
```

The static comparison uses the earlier session's object with an identical
`SemaSpecOp.Resolve.cpp` source against this batch's object, built with the same
DevMode configuration/toolchain. Assembly includes local labels. Validation
belongs to the batch tested; a conflict-free integration alone does not certify
subsequent concurrent changes on `master`.
