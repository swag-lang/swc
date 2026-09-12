# Tooling Backlog

The build, the sandbox, and the test harness — everything that surrounds the compiler rather than
being compiled by it.

[README.md](README.md) defines the shared backlog conventions.

### repo.tooling.005 — An incremental Release build can mix two versions of the diagnostic table

- Recorded: 2026-09-04 15:19
- Updated: 2026-09-12 10:21 — Record the confirmed stale-object recurrence and the remaining invalidation uncertainty.
- Area: tooling
- Found while: the Release rung of a repository health reset, on sources whose only recent change
  was in semantic analysis
- Observation: the Release compiler built incrementally over an object tree left by an earlier
  session reported the wrong diagnostic for an unknown symbol: `var v: MissingType` came back as
  `modifier 'MissingType' needs an integer type, found` — the message of the id that follows
  `sema_err_unknown_symbol` in `Errors.Sema.msg`. The DevMode compiler built from the same sources
  reported it correctly. These results are consistent with translation units compiled against
  different diagnostic identifiers, but the dependency that failed to invalidate was not isolated.
  The current `pch.h` contains no diagnostic declarations: `DiagnosticDef.h` takes identifiers
  from `Errors.inc` and `Notes.inc`, while `Diagnostic.cpp` takes message variants from the
  separate `.msg` catalogs and maps each group through its explicit `DiagnosticId`.
- Evidence: 2026-09-04, sources at `SWC_BUILD_NUM` 343. `MSBuild swc.sln /p:Configuration=Release`
  produced a binary that failed nine `bin/unittests/errors/sema` fixtures whose expected ids never
  matched; recompiling `Diagnostic.cpp` alone changed nothing; `MSBuild /t:Rebuild` on the same
  sources produced a binary that reports `unknown symbol 'MissingType'` and passes the suite.
- Confirmed recurrence (2026-09-12, Release 0.1.489): the local-function expansion fixture
  emitted `sema_note_generated_source_root` where it expected `sema_note_expansion_invoked_here`.
  Commit `8811b59ae` added one error identifier before the note identifiers; the old numeric value
  therefore selected exactly the preceding note. `SemaClone.obj` dated 2026-09-11 16:38, while
  `Errors.Sema.inc` dated 21:48. Touching only `SemaClone.cpp`, without changing its contents,
  recompiled that object and made the unchanged fixture pass. This confirms mixed enumeration
  versions in the executable; it does not identify why the earlier build retained the object.
- Attribution limit: the tracked reads inspected after recompilation included `Errors.Sema.inc`,
  but that section had already been rewritten; the historical tracking state is unavailable.
  No dependency-tracking exclusion was found in the project. The health-reset prompt now uses
  `/t:Rebuild` for both initial compiler baselines, which avoids retaining these objects without
  repairing the unresolved incremental-invalidation cause.
- Next: reproduce a catalog edit over a warm Release object tree and inspect the MSBuild tracked
  reads for `DiagnosticDef.h`, its `.inc` catalogs, and the affected translation units. Distinguish
  an identifier insertion in `.inc` from a message-only edit in `.msg`, then fix the dependency
  that fails to invalidate.
- Complete when: an incremental Release build after ids are added to an `.inc` catalog either
  recompiles what depends on them, or cannot produce a binary whose reported id and printed text
  disagree.

### repo.tooling.003 — Matroska timing and display-size cases lack reproducible fixtures

- Recorded: 2026-08-25 22:01
- Updated: 2026-09-12 05:40 — Distinguish existing edited fixtures from the two uncovered header cases
- Area: tooling
- Found while: fixing two defects a real film exposed and trying to pin them with a fixture
  (2026-08-25): a track whose `DefaultDuration` says one millisecond, and one whose display size
  differs from its stored size.
- Observation: the original fixture attempts used FFmpeg through PyAV, which
  writes what the source stream says and nothing else. Rewriting one stream into a new file with
  a chosen sample aspect drops it (`add_stream_from_template` fixes the parameters, and building
  the stream by hand loses the setup headers, after which the fixture decodes nothing). Editing
  the EBML by hand means growing every parent size around the inserted element, which is more
  machinery than the test it would serve.
- Evidence: three attempts during the 2026-08-25 investigation produced a file reporting
  `container_sar 1` or decoding zero frames. The current fixture collection also contains edited
  Matroska headers, including content stripping and codec delay, documented in
  `bin/std/modules/video/src/tests/datas/THIRDPARTY.md`. No reusable EBML fixture producer is
  checked in. `matroska.test.swg` checks the absent-display-size fallback, but neither the
  misleading one-millisecond default duration nor a display size different from the stored size.
- Consequence: two behaviours are exercised only against files that cannot be committed — the
  frame rate a stream's own timestamps state when its track lies about it, and the display size
  of a track whose samples are not square. Both were verified on real films of a personal library
  and neither has a fixture.
- Next step: write the fixture generator this repository needs rather than borrowing one — a
  small Swag or Python producer that emits an EBML document element by element, so a test can ask
  for exactly the header a defect needs. `std/video` already writes Matroska nowhere, so this is
  test tooling rather than a module feature.
- Complete when: a checked-in producer reproducibly creates both small header cases and tests
  verify timestamp-derived frame rate and non-square display geometry without private media.

### repo.tooling.009 — Reassess Release LTO after iteration costs are controlled

- Recorded: 2026-09-08 08:02
- Evidence: Release LTCG links took several minutes during the constant-address investigation,
  including after a change to one semantic-analysis source. The owner requested disabling LTO
  for current development and reconsidering it later. `swc.vcxproj` now disables whole-program
  optimization and link-time code generation while retaining the other Release optimizations.
- Next: measure compiler throughput, binary size, peak memory and incremental link time with
  and without LTO under comparable load before restoring it; consider a separate distribution
  build if shipping performance justifies the cost but routine iteration does not.
- Complete when: the documented build policy preserves practical Release iteration and any
  restored LTO has a measured benefit and an explicit place in the build workflow.

### repo.tooling.008 — Record module timings with load observed during each sample

- Recorded: 2026-09-07 10:37
- Updated: 2026-09-07 11:57 — Record the GUI memory increase and the slower loaded documentation pairs
- Evidence: the compilation campaign used a private tracked-source mirror for `gui`, `pixel`,
  and `ogl`, because the full test tool cleans `bin/std` outputs. A CPU admission check before
  a sample did not prevent another campaign from starting during it. Three alternated pairs
  measured the same GUI compiler between 8.77 and 45.43 seconds. The existing benchmark's
  performance-core affinity mask provides a separate scheduling control; it must not be mixed
  with ordinary unpinned build results.
- Rejected experiment: retaining SSA block scratch storage across rebuilds was expected to save
  a small part of allocation cost. Compiler 393 versus 394, six workers, three unpinned pairs,
  produced median paired candidate/baseline ratios of 0.897 wall / 0.951 CPU for GUI, but
  1.085 wall / 1.046 CPU for Pixel. Pixel resident peak ratio was 1.029 and committed peak 1.017.
  The variance is too large to attribute those differences to the change. The experiment was
  removed; it did not establish a speed gain without a memory cost. Raw data and the external
  profile are retained in [the campaign report](../bench/results/compilation/20260907/README.md).
- Fixed-dependency control: five alternated GUI pairs kept all 69 dependency files byte-identical
  and used the six-performance-core affinity mask. Compiler 393 versus baseline 390 gave median
  paired ratios of 0.942 wall and 0.886 CPU, but 1.037 resident peak and 1.048 committed peak.
  Background CPU still differed across pairs. The existing-data lookup changes do not retain a
  new cache, but these measurements do not establish that faster phases preserve peak overlap.
  Treat the GUI memory increase as unresolved, not as a cost hidden by a timing win.
- Documentation control: two complete A/B then B/A pairs of the existing `doc_std` workload
  measured baseline 51.9/49.7 seconds versus candidate 122.3/131.9 seconds. Its paired wall
  ratio is 2.505 and CPU ratio 2.197. The slow region moved from dependency builds in one
  candidate run to HTML generation in the other. The wrapper did not capture during-run CPU
  deltas for this older workload, so a load explanation is unproven; investigate this observed
  regression under steady load before claiming an overall compile-speed improvement.
- Next: add opt-in module-only workloads to the recorded compilation instrument and retain
  both preflight admission and system CPU deltas across the timed process. Distinguish warm
  dependencies, whole dependency rebuilds, pinned controls, and ordinary builds in the results.
  Repeat the GUI control under steady load and isolate each retained compiler change to explain
  the peak-memory difference before setting a regression budget.
- Complete when: GUI, Pixel, and OGL regressions can be assessed with repeatable paired module
  timings and memory peaks, and a sample disturbed after admission is identified in the record.
- Related: compiler.optimization.029.

### repo.tooling.007 — Separate formatter input preparation from formatter cost

- Recorded: 2026-09-06 15:21
- Evidence: on 2026-09-06, the format benchmark's private source copy omitted `.swc-format`
  files and three maintenance input groups. It rewrote 580 files where the real `bin/` dry run
  rewrote none. The mirror now preserves configuration and follows `tools/format.swgs`.
  Fresh copies still spend most sampled worker time opening files: 351 of 401 `FormatJob`
  samples include `SourceFile::loadContent`, mostly `NtCreateFile`. Original sources instead
  spend 166 of 220 samples in `Formatter::prepare`; only 19 include indentation.
- Rejected experiment: sharing the indentation pass's two line-column computations and reusing
  their vector was predicted to save 2–5% of whole-format CPU. Eleven order-alternated pairs
  on all maintenance roots, Release build 381 versus the candidate, six workers, gave median
  paired candidate/baseline ratios of 1.009 wall, 1.012 CPU and 0.990 peak committed memory.
  Median wall times were 1,255 and 1,306 ms. All 3,458 mirrored files, including configuration,
  had identical output hashes. The optimization was removed because it showed no speed gain.
  Shared-host activity varied during the measurement; these are not clean campaign records.
- Next: measure fresh-copy and original-source formatting separately, attribute the opening
  delay externally, and profile the formatter's dominant passes before choosing another change.
- Complete when: the campaign distinguishes input-opening cost from formatting CPU and a retained
  optimization has an order-alternated speed gain with identical output and measured memory.

### repo.tooling.002 — A differential harness must line pictures up by time, not by rank

- Recorded: 2026-08-25 16:27
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Area: tooling
- Found while: measuring the video library against FFmpeg.
- Observation: FFmpeg numbers the pictures it emits densely, while this reader numbers them the
  way the container does. The two disagree wherever a container holds a sample that produces no
  picture — a plane that codes nothing, a leading picture a random access point says to skip, or
  an access unit before the first one that can be reconstructed. Neither numbering is wrong: a
  player seeks by the frame number its container states, while FFmpeg hands out packets and frames
  with timestamps and drops samples that emit no frame.
- Evidence: comparing picture `k` against FFmpeg's picture `k` reported defects for two files in
  the measured library; both proved bit-exact once their pictures were lined up by presentation
  time.
- Next step: make the differential harness record the timestamp of each reference picture and ask
  this reader for the rank that carries it before comparing decoded pixels.
