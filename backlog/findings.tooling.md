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

### F-180 — `dm` does not choose the compiler that generates the standard library API

- Area: tooling
- Found while: changing what a generated module API writes, and failing to see the change for
  several build cycles.
- Observation: a repository tool is a script, and `bin/swc.exe` is what runs it. The script's own
  `#import("core", location: "swag@std")` therefore builds `bin/std` — and *generates every module
  API in it* — with the Release compiler, before the `dm` argument selects `swc_devmode` for the
  module builds the tool was asked to run. A change to the API generator built only in DevMode is
  invisible: the DevMode compiler then reads an API the Release one wrote, reports every module
  `up-to-date`, and produces artifacts that disagree with the sources.
- Evidence: with a DevMode compiler that omits an attribute from the generated API and a Release
  compiler that still writes it, `swc tools/std.swgs dm build core` after `rm -rf bin/std/.output`
  regenerates `core.swg` in the *old* format in under half a second, reporting
  `module core • up-to-date`. The first lines of the run give it away — a `swag run • tools` block
  builds `std [core]` before the `swag build • std [core]` block starts. Rebuilding Release makes
  the same command produce the new format.
- Next step: decide what `dm` means. Either the tool re-execs itself under the requested compiler
  so one binary does the whole run, or the script's dependency build is separated from the build the
  tool performs, so the two never write the same `.output`. Until then, any change to the module API
  generator has to be built in both configurations before it can be observed.
