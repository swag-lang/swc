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


### repo.tooling.005 — Fifteen recorded goldens do not match what master renders

- Area: tooling
- Found while: attributing the golden campaign for a change to `pixel/src/poly/clipper.swg`
  (2026-09-03).
- Observation: `swc tools/goldens.swgs dm test` on a pristine worktree at `62182ab0c`, with no
  local change at all, reports fifteen failures: the four `properties.*` snapshots in
  `std/gui`, the ten `main.menu.*` / `library.menu.*` snapshots in `apps/swagcapture`, and
  `about` in `apps/swagscope`. Everything else is green — 91 in `std/pixel`, 46 in `std/gui`,
  33 in `apps/swagscope`, 1 in `apps/swagvault`.
- Evidence: the same fifteen were dismissed on 2026-09-03 as another agent's in-flight work in a
  shared checkout. They are not: a `git worktree add --detach` of `62182ab0c` with nothing but
  the two compiler executables copied in reproduces every one of them. The shapes differ:
  `properties.*` moves 28 to 82 pixels by up to 194 of one channel, always starting at `x == 0`;
  the swagcapture menus move exactly 2 pixels by 1 to 48; `about` moves 4895 by up to 152, which
  reads as text rather than as a widget.
- The cost is not the red: it is that every campaign has to re-run a pristine base to tell these
  apart from its own change, which is two extra module builds per validation.
- Next: record one of them from the pristine tree and diff the recorded PNG against the promoted
  one to see whether the difference is a machine's fonts and display scale or a real drift; the
  three groups may not have the same answer. `about` moving text is the one to read first.
- Complete when: `swc tools/goldens.swgs dm test` is green on master, or each surviving snapshot
  names what makes it machine-dependent.
