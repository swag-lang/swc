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

Commands, from the corresponding campaign worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm sema --num-cores 6 --rebuild
```

Validation evidence belongs to the source batch tested; a conflict-free merge
alone does not certify subsequent concurrent changes on `master`.
