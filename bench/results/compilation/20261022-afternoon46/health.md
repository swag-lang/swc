# Compiler health, 2026-10-22 afternoon

Prompt 6 starts at `74ba1680d3` in the external `prompt6` worktree under
`%LOCALAPPDATA%/swc-agent-builds/alternate46-20261022-1515`, on
`quality/prompt6-alternate-20261022-1515`, alternating with prompt 4 until
18:00 Europe/Paris. Builds/tests use fresh load admission, six workers and
checkout-local compilers. Temporary/cache roots are external. `SWC_BUILD_NUM`
is unchanged. No timing or peak-memory measurement is made.

| Batch | Mechanical change and equivalence | Validation |
| --- | --- | --- |
| 6.1 | Share the switch-case and case-expression collectors through one span-parameter helper. Both copies had the identical vector construction, valid-span guard, append and return; all seven callers now pass their original span. Allocation, order, invalid-span behavior and output are unchanged. The shared helper retains 34 instructions, three calls and a 0x40-byte stack reservation; each old copy had the same counts/frame. The inspected switch callbacks retain their instruction/call counts, final offsets and stack frames. | DevMode build; all 95 switch-focused native tests pass in `devmode`, including chunked lists, dynamic/interface switches and cross-AST inlining. |

Commands, from this worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native --file-filter switch --num-cores 6 --rebuild
```

This file-local batch changes no shared header, architecture or conditional
source surface, so DevMode is sufficient. Static object comparison uses the
earlier session's unchanged switch source and the same configuration/toolchain.
Results belong to the source actually tested, before prompt-4 integration is
synchronized into this worktree.
