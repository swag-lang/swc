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

### F-166 — The sVaultDrive surface golden no longer matches what the app paints

- Area: tooling
- Found while: running the full `tests.swgs dm` campaign on the `#simd` worktree.
- Observation: `vaultdrive.surface` no longer matches its golden in `fast-debug`: 852 pixels
  outside tolerance, maximum channel difference 51, first difference at (482, 766) inside the
  disabled "Create encrypted vault" button — face pixels shift by about 3 per channel, the
  large deltas sit on anti-aliased edges. The failure is deterministic and does not come from
  the simd branch: a compiler rebuilt from the branch base `f98a3a74a` (with identical gui,
  pixel, and app sources) fails the same way, and the only commit touching `bin/std` between
  the golden's recording (`08800359f`, same day) and that base adds an `ImageView` method that
  sVaultDrive never calls.
- Evidence: `swc tools/apps.swgs dm test sVaultDrive`; the differing image is written next to
  the golden as `vaultdrive.surface.actual.png`. The compiler's own configuration is not the
  cause: `swc tools/apps.swgs test sVaultDrive`, driven by the Release-built compiler from the
  same sources, produces the identical difference — 852 pixels, maximum channel difference 51,
  first at (482, 766) — so the two builds of `swc` agree and the golden disagrees with both.
- Next step: compare the recorded golden against the current one pixel by pixel on the disabled
  button face and decide which is right, then either re-record with `swc tools/goldens.swgs`
  or find the `bin/std` change that moved the disabled-face blend. Comparing configurations is
  finished; what is left is deciding whether the paint or the recording is stale.
