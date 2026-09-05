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

### repo.tooling.004 — A tool relaunched under the selected compiler can relaunch itself forever

- Area: tooling
- Found while: building the standard library under the interval allocator gate for compiler.optimization.024's A/B.
- Observation: `relaunchToolIfNeeded` (`tools/src/context.swg`) re-runs the script under the
  selected compiler with `--rebuild` whenever the running executable differs from the selected
  one, and nothing marks the relaunched process as such. When that decision misfires in the
  relaunched process, every generation rebuilds the tool's dependencies and spawns the next. It
  misfired once: a fresh worktree, `SWC_INTERVAL_RA=*`, a user-supplied `--rebuild`, and a
  checkpoint of the interval allocator compiling the tool's own `core` gate-on — 55 nested
  `swc.dm.exe` processes in nine minutes, stopped by hand.
- Evidence: 2026-08-27, branch `t563-r1` at `d0621af96`; the log repeats `swag run • tools`,
  `module core`, `workspace std [core]`, `tuned 644 functions`. The same command with the
  compiler that followed, and every variant with only one of the conditions, runs once; the
  comparison that disagreed under the gate was not isolated.
- Next: make the relaunch non-recursive — the relaunched process carries a marker (an
  environment variable or a reserved argument) and refuses to relaunch again, reporting both
  paths instead — then look for what disagreed under the gate.
- Complete when: a relaunched tool is marked as such and never relaunches again, proven by the
  four-condition reproducer above running once.

### repo.tooling.005 — An incremental Release build can mix two versions of the diagnostic table

- Area: tooling
- Found while: the Release rung of a repository health reset, on sources whose only recent change
  was in semantic analysis
- Observation: the Release compiler built incrementally over an object tree left by an earlier
  session reported the wrong diagnostic for an unknown symbol: `var v: MissingType` came back as
  `modifier 'MissingType' needs an integer type, found` — the message of the id that follows
  `sema_err_unknown_symbol` in `Errors.Sema.msg`. The DevMode compiler built from the same sources
  reported it correctly. A translation unit compiled against an older precompiled header raises
  the ordinal that enum had then, while `Diagnostic.cpp` maps ordinals through the table it was
  compiled with: the two disagree by however many ids were added in between.
- Evidence: 2026-09-04, sources at `SWC_BUILD_NUM` 343. `MSBuild swc.sln /p:Configuration=Release`
  produced a binary that failed nine `bin/unittests/errors/sema` fixtures whose expected ids never
  matched; recompiling `Diagnostic.cpp` alone changed nothing; `MSBuild /t:Rebuild` on the same
  sources produced a binary that reports `unknown symbol 'MissingType'` and passes the suite.
- Next: find what the Release configuration fails to invalidate — the precompiled header is the
  first suspect, since the diagnostic enum reaches every translation unit through `pch.h` and the
  message table reaches only `Diagnostic.cpp`. Either make the header dependency explicit, or make
  the id-to-message mapping independent of the enum's ordinals.
- Complete when: an incremental Release build after ids are added to a `.msg` file either
  recompiles what depends on them, or cannot produce a binary whose reported id and printed text
  disagree.

### repo.tooling.006 — A tag-gated source is compiled by nothing, because a tag is not part of the cache key

- Area: tooling, compiler/incrementality
- Found while: the Release rung of a repository health reset, reaching `vault.swgs` for the first
  time since the missing-return rule landed
- Observation: `bin/apps/modules/swagvault/src/tests/integration.win32.swg` opens with
  `#global if WINDOWS and #hastag("vault.integration")`, so every ordinary build removes it. It had
  stopped compiling a week earlier — `findFreeMountPoint` ends on `failWith`, which is a call, not
  a `fail` — and nothing said so until someone needed the tag. It is the only source in `bin/` that
  a tag switches on as a whole; the other thirteen `#hastag` sites gate expressions inside files
  that are always compiled.
- Why the obvious check does not work: `swc sema -w bin/apps -m swagvault --tag vault.integration`
  answers `up-to-date` right after the untagged build, because the tag set is not part of the
  artifact cache key. `vault.swgs` already works around this by passing `--rebuild` with the tag
  (`tools/src/maintenance.swg`), and that rebuilds the workspace's std dependency copies too:
  measured at 24.5 s on a warm tree, against 1.3 s for the semantic pass itself and 1 min 34 s for
  the whole of `build.swgs`. Paying a quarter of the build campaign to compile one file is why this
  is an entry rather than a check.
- Next: put the registered tag set in the artifact cache key, so a tagged compilation of an
  untagged artifact is a miss rather than a hit. `vault.swgs` can then drop its `--rebuild`, and a
  tagged semantic pass becomes cheap enough for `build.swgs` to run one per tag-gated module.
- Complete when: `swc sema` with a tag recompiles a module the untagged build just made, and
  `build.swgs` fails when a `#hastag`-gated source stops compiling.
