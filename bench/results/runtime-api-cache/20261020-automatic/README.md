# Automatic runtime/API machine-code cache

Runtime and imported API machine-code reuse is automatic, with no public
enable/disable option. `--rebuild` invalidates the current compiler's archive,
reads no old entries and publishes fresh eligible records. Requests which bypass
emission reuse, including optimizer statistics, still invalidate the old archive.

The retained reader maps a bounded archive read-only. A contiguous index precedes
the bodies, so lookup does not copy or visit unused bodies. Each record retains
its generation while it is validated and decoded; code and references are then
rebound to the current compiler instance. Immutable records avoid intermediate
payload copies. Publication builds a complete archive in memory and releases the
compiler's own old mappings before replacing the file. Other active readers keep
their old bytes. The mapped-file fallback may briefly leave the cache path absent
between two renames; a reader then compiles normally and never sees partial bytes.

SHA-256 processes input blocks and fragments without allocating a padded copy of
the entire input. The machine-code checksum and its binding to the key are unchanged.

The parse-image prototype, its public option, AST allocation tracking and dedicated
serialization helpers/tests have been removed. Source loading, lexing, parsing,
semantic analysis and initial IR generation still run. The cache skips backend
optimization, register allocation and encoding. Resolved semantic interfaces and
lookup before IR generation remain separate work in `compiler.core.001` and
`compiler.core.030`.

## Comparison

The control is commit `35e65ba5d6`, with its machine cache enabled and syntax cache
disabled. New comparisons therefore measure additional changes beyond the
[already validated cache](../20261020/README.md), which reduced complete warm
build time by 33.7% for runtime, 24.4% for core, 15.6% for pixel and 4.5% for GUI.
Those historical reductions are not combined with another campaign's ratios.

- Control SHA-256: `4c1777b48ccd3a494d3a393493ec486a62097d8fe26511d85d3e91880b7b7e8a`.
- Final candidate SHA-256: `4b4c17b8bf5e7f77e2b8c1295a830ca45f15e38a6b24c29280d7ef1f93706285`.
- Both compilers use the same runtime, generated API bytes and devmode native
  libraries. The eight-module GUI dependency closure was rebuilt during the
  mapped-reader iteration; dependency production stays outside the timer.
- Complete native builds use the Release compiler, devmode program configuration,
  six workers, one logical processor per performance core and fresh native output
  directories for every sample. Pilots populate and reuse both compilers' caches;
  their generated programs execute separately and must print `42`.
- Every invocation passes shared-machine CPU and memory admission. The JSON names
  the actual CPU threshold, compiler hashes and arguments. No build or test from
  this task overlaps a timed campaign. Other work can start after admission.
- `off` denotes the preserved control with its machine cache enabled; `warm`
  denotes the current compiler's automatic cache. Timings include all cache loading,
  hashing, remaining emission and shutdown publication. Interrupted campaigns are
  checkpointed and unfinished cases do not constitute a completed comparison.

Reproduce with an external control executable and explicit runtime/std resources:

```powershell
py -3 bench/parsecache.py --scratch "C:\path\outside-checkout" --against "C:\baseline\swc.exe" --against-arg=--machine-cache --against-arg=--no-parse-cache --only gui pixel core runtime --reps 5 --max-cpu 65
```

The two cache arguments belong to the historical control. The current compiler
accepts neither switch.

## Rejected syntax-cache experiments

[eager-pilot.json](eager-pilot.json) keeps five pairs for runtime and GUI with an
eager archive reader, SHA-256
`0d01467c3c17f526d4f8319e08a225d446ebd5fe421ec04fe4b77fa2b0d21dc0`.
Its paired wall ratios were 1.1073 and 1.0239. It loaded and materialized the whole
archive, which held 70 distinct sources and occupied 16,213,572 bytes after GUI.

[mapped-runtime-pilot.json](mapped-runtime-pilot.json) keeps nine runtime pairs
for the mapped syntax reader, SHA-256
`9dd5720776afeeaf1be54566a6d42ed03963f1431bed30a182cde425018878ed`.
Its paired wall ratio was 1.06498 and CPU ratio 0.96154. Less CPU did not justify
increased whole-process time, so runtime syntax reuse was removed. A subsequent
API-only syntax trial could not establish a reliable gain before the time limit
under shared-machine contention. Syntax reuse was therefore removed entirely.
This does not establish that every future semantic-interface design is unprofitable.

## Validation

The mapped-reader iterations passed ordinary C++ tests, the filesystem suite,
automatic cold/warm native and JIT integration, changed API bodies and literals,
consumer layouts, callee effects, program configuration, compiler identity,
diagnostics, corruption recovery and concurrent publication. The Release compiler
also passed 3,904 native-suite tests in JIT and native execution after `--rebuild`
and on warm archives. Both compiler executables passed all seven workspace
consumer tests in devmode program configuration after a forced rebuild.

[Release](verification-release.json) and [DevMode](verification-devmode.json)
retain the integration checks from the final publication-path iteration before
the parse-image prototype was removed.

The final revision built with both DevMode and Release configurations. All 1,496
ordinary C++ tests passed after removing the prototype's three dedicated tests.
The new mapped-file replacement regression also passed in the earlier full
filesystem-enabled run (1,562 tests before removal of those three tests).

The final forced-rebuild scenarios passed with
[Release](final-rebuild-release.json) and [DevMode](final-rebuild-devmode.json).
They pin old archives through the same file-sharing and read-only mapping API as
compiler readers, insert an unused sentinel, force rebuild, and verify that the
sentinel disappears, no function is reused by that build, the old reader's bytes
are intact, and the next ordinary build reuses newly published records. They also
verify that `--rebuild --optimizer-stats` removes the old archive while a reader
still maps it, despite producing no replacement machine-code records.


## Final deadline-limited comparison

[final-attempt.json](final-attempt.json) preserves every recorded pilot and sample;
[final-summary.json](final-summary.json) summarizes completed cases only. The final
campaign used a 65% CPU admission ceiling, retained the project's full memory
thresholds, and ran no other build or test from this task concurrently. Repeated
memory admission waits prevented a complete four-consumer series before 17:00
Europe/Paris. Incomplete cases do not establish a before/after comparison.

No case completed its five paired samples before the cutoff.

These shared-machine samples do not certify an additional whole-command gain
across runtime, core, pixel and GUI. The earlier complete opt-in campaign remains
the evidence for the machine-code cache's original benefit. The retained changes
make that cache automatic, preserve forced invalidation, remove the unsuccessful
syntax layer and reduce archive-copying/allocation work; they do not replace the
still-unfinished semantic-interface cache.
