# Structural compilation savings, 2026-10-21

This time-bounded prompt-4 session starts at `4af083bc14`, on
`perf/prompt4-20261021-1614` in an external worktree, and runs until 18:00
Europe/Paris. Validation uses the checkout-local DevMode compiler and at most
six workers after fresh machine-load admission. `SWC_BUILD_NUM` is unchanged.
No timing campaign or profiler is run; compilation-time targets remain unverified.

| Retained change | Compiler work removed | Equivalence and storage evidence |
| --- | --- | --- |
| Allocate stack-displacement scratch without clearing unread entries | An initial eight-byte zero write per instruction | The entry and every first-discovered successor receive their offset before being queued. Later transitions retain that initialized offset, including unknown states. Unreachable slots are never read. Capacity, allocation count, propagation and results are unchanged. The helper loses one `memset`, shrinks from 2,237 to 2,018 code bytes and reserves 208 rather than 224 stack bytes. |

The first batch builds successfully and passes all 1,535 default C++ tests,
including backend stack-frame, promotion and register-allocation coverage.
The default C++ command omits filesystem tests requiring `--dev-full`.

Commands run from the campaign worktree:

```text
MSBuild.exe swc.vcxproj /t:Build /p:Configuration=DevMode /p:Platform=x64 /m:6 /p:SwcCompileJobs=6
bin/swc.dm.exe unittest --num-cores 6
```

C++ validation uses a session-specific temporary/cache root outside all checkouts.
Static object and disassembly inspection establishes code shape, not elapsed-time
or peak-memory performance. Benchmark history and the backlog are unchanged.

Rejected leads: every current natural-loop discovery caller already checks for
backward edges, so adding the same guard to the shared discovery helper would
not remove a live traversal.
