# Tooling Backlog

The build, the sandbox, and the test harness — everything that surrounds the compiler rather than
being compiled by it.

[README.md](README.md) defines the shared backlog conventions.

### repo.tooling.002 — A differential harness must line pictures up by time, not by rank

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

### repo.tooling.003 — A Matroska fixture cannot state what a real file states about itself

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

### repo.tooling.005 — An incremental Release build can mix two versions of the diagnostic table

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
- Next: reproduce a catalog edit over a warm Release object tree and inspect the MSBuild tracked
  reads for `DiagnosticDef.h`, its `.inc` catalogs, and the affected translation units. Distinguish
  an identifier insertion in `.inc` from a message-only edit in `.msg`, then fix the dependency
  that fails to invalidate.
- Complete when: an incremental Release build after ids are added to an `.inc` catalog either
  recompiles what depends on them, or cannot produce a binary whose reported id and printed text
  disagree.

### repo.tooling.007 — Separate formatter input preparation from formatter cost

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
