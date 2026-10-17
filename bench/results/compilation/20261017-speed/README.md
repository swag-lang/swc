# Structural compilation savings, 2026-10-17

This prompt-4 pass starts at `46c33a053c` on `perf/prompt4-20261017` in an external
worktree. It uses only that worktree's DevMode compiler, with six workers.
`SWC_BUILD_NUM` remains 1173. The existing compilation reports guided selection
of Micro analysis work; no timing, profiling, or benchmark campaign was run.

| Retained change | Compiler work removed | Equivalence argument |
| --- | --- | --- |
| Precompute record-store byte effects (`082309ef7`) | Repeated operand reads, width/mask construction, and immediate-byte scans during record dataflow sweeps; map nodes for reads | Each store has a fixed defined-byte mask and zero-byte mask. Applying those masks produces the same outgoing state. Instructions remain unchanged throughout the analysis. |
| Save record states only for partial stores (`9f8be1e9f`) | State-map lookups and insertions for reads and whole-word writes | Only partial stores consult the saved state when rewriting. The complete access validation and dataflow remain in place. |
| Intersect forward dominators by instruction order | RPO-rank stores for reachable instructions and repeated rank-array reads during intersections | Every edge in this path points forward, so instruction indices have the same ordering as the previously stored ranks. The existing SSA helper now serves both analyses; cyclic graphs retain their previous algorithm. |

The changes preserve traversal order, promotion choices, virtual-register assignment,
instruction rewriting, and graph storage. Existing C++ shape checks cover record
field clearing and zero-byte facts. The dominator oracle compares every possible
entry and node pair against reachability with a node removed, with and without loops;
SSA tests also cover disconnected forward-only roots.

Validation ran from the campaign worktree:

```text
MSBuild.exe swc.sln /t:Build /m:6 /p:Configuration=DevMode /p:Platform=x64 /p:SwcCompileJobs=6 /nologo /v:minimal
bin\swc.dm.exe unittest --num-cores 6 --verbose-unittest
bin\swc.dm.exe --num-cores 6 tools\unittests.swgs dm native -bc devmode --file-filter record_word_paths.swg --num-cores 6 --rebuild
bin\swc.dm.exe --num-cores 6 tools\unittests.swgs dm native -bc devmode --file-filter optimizer --num-cores 6 --rebuild
```

The first build, 1,419 C++ tests, and the single native record test passed before
integrating the first batch. An incremental DevMode build and a fresh 1,419-test
C++ run then passed with all three changes. These are the default internal C++
tests; 60 filesystem tests requiring `--dev-full` were excluded. The final native optimizer selection
checked 289 inputs including the runtime and passed 299 tests. Every command exited
zero. The native tool invocations used separate external `TEMP`/`TMP` cache roots.
Machine-load admission preceded each build and test. Formatting and `git diff --check`
also passed. No broader repository campaign or Release-compiler build was needed
for these local analysis changes.

The compilation-time targets remain unverified. This is a completed, focused pass,
not a claim that the speed campaign has exhausted every possible structural saving.
Worklist visitation changes were left aside because changed early-exit priority
would require measurement to establish a saving.
