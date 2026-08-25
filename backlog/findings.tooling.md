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

### F-200 — A Matroska fixture cannot state what a real file states about itself

- Area: tooling
- Found while: fixing two defects a real film exposed and trying to pin them with a fixture
  (2026-08-25): a track whose `DefaultDuration` says one millisecond, and one whose display size
  differs from its stored size.
- Observation: every Matroska fixture of `std/video` is muxed with FFmpeg through PyAV, which
  writes what the source stream says and nothing else. Rewriting one stream into a new file with
  a chosen sample aspect drops it (`add_stream_from_template` fixes the parameters, and building
  the stream by hand loses the setup headers, after which the fixture decodes nothing). Editing
  the EBML by hand means growing every parent size around the inserted element, which is more
  machinery than the test it would serve.
- Evidence: three attempts, all in this session; the resulting file reports `container_sar 1` or
  decodes zero frames.
- Consequence: two behaviours are exercised only against files that cannot be committed — the
  frame rate a stream's own timestamps state when its track lies about it, and the display size
  of a track whose samples are not square. Both were verified on real films of a personal library
  and neither has a fixture.
- Next step: write the fixture generator this repository needs rather than borrowing one — a
  small Swag or Python producer that emits an EBML document element by element, so a test can ask
  for exactly the header a defect needs. `std/video` already writes Matroska nowhere, so this is
  test tooling rather than a module feature.
