# Findings — Tooling

The build, the sandbox, and the test harness — everything that surrounds the compiler rather than
being compiled by it.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-127 — Compiler builds and tool-driven runs are CPU-capped for the development machine

- Area: tooling
- Found while: keeping the machine responsive while builds and test campaigns run alongside other work
- Observation: `swc.vcxproj` caps `/MP` through `SwcCompileJobs` (logical processors minus 4, overridable with the `SWC_COMPILE_JOBS` environment variable or `-p:SwcCompileJobs=N`), and the tools inject a default `--num-cores` with the same policy into every compiler they start (`withCoreBound` in `tools/src/context.swg`, an explicit `--num-cores` or `-j` still wins). Both caps are a temporary comfort measure for the current development period, where one machine runs the IDE, several AI agents, and their campaigns at once; the reserve of 4 logical cores is arbitrary rather than measured.
- Evidence: 22-logical-processor machine saturated by an unbounded `/MP` compile plus unbounded `swc` job managers; caps added 2026-08-13.
- Next step: when the machine stops hosting several concurrent agents, or when the tools run on a dedicated CI machine, re-evaluate both caps — remove them so builds and campaigns take the whole machine again, or keep them behind an explicit opt-in.

### F-143 — A workspace run rebuilds its unchanged executable after a test build

- Area: tooling
- Found while: validating dynamic shared-library lifecycle hooks with the DevMode workspace suite
- Observation: `swc tools/unittests.swgs dm workspace` reproducibly reaches the final `consumer_exe` run but recompiles `consumer_exe.exe` after building and reusing `consumer_exe.test.exe`; the suite then stops with `Workspace run recompiled its unchanged executable after a test build.`
- Evidence: reproduced twice on 2026-08-16, once from the full DevMode campaign and once with the isolated workspace suite. The dynamic-library lifecycle test, both native executions, and the preceding reuse check for `consumer_exe.test.exe` all pass.
- Next step: compare the regular executable manifest and dependency fingerprints immediately before and after the native test build, then identify which test-artifact publication mutates an input owned by the regular artifact.
