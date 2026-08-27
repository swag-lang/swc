# Tooling Backlog

The build, the sandbox, and the test harness — everything that surrounds the compiler rather than
being compiled by it.

[README.md](README.md) defines the shared backlog conventions.

### F-127 — Compiler builds and tool-driven runs are CPU-capped for the development machine

- Area: tooling
- Found while: keeping the machine responsive while builds and test campaigns run alongside other work
- Observation: `swc.vcxproj` caps `/MP` through `SwcCompileJobs` (logical processors minus 4, overridable with the `SWC_COMPILE_JOBS` environment variable or `-p:SwcCompileJobs=N`), and the tools inject a default `--num-cores` with the same policy into every compiler they start (`withCoreBound` in `tools/src/context.swg`, an explicit `--num-cores` or `-j` still wins). Both caps are a temporary comfort measure for the current development period, where one machine runs the IDE, several AI agents, and their campaigns at once; the reserve of 4 logical cores is arbitrary rather than measured.
- Evidence: 22-logical-processor machine saturated by an unbounded `/MP` compile plus unbounded `swc` job managers; caps added 2026-08-13.
- Next step: when the machine stops hosting several concurrent agents, or when the tools run on a dedicated CI machine, re-evaluate both caps — remove them so builds and campaigns take the whole machine again, or keep them behind an explicit opt-in.

### F-198 — A differential harness must line pictures up by time, not by rank

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

### F-201 — A test fixture the repository stores as text fails on any fresh checkout

- Area: bin/std
- Found while: running the standard-library suites in a second worktree for T-563.
- Observation: `gui`'s `htmlview.test.swg` asserts `view.fileSize == 8_153_570` for the
  fixture `html.rustdoc-large.html`, which is the size the file has with line feeds. The
  repository checks it out with `eol=crlf` like every other text file, so a fresh worktree gets
  8,224,706 bytes and the test fails. It passes in the main worktree only because that copy was
  checked out on 31 July, before the attribute covered it.
- Evidence: 2026-08-26. `git check-attr -a` on the fixture answers `text: auto` and `eol: crlf`;
  `git ls-files --eol` answers `i/lf w/crlf`. The file measures 8,224,706 bytes in a worktree
  created this month and 8,153,570 in the one created in July. Normalising the working copy to
  line feeds makes the whole suite pass (611 tests).
- Next step: a fixture is an input, not a source file — give the test data directories a
  `-text` rule in `.gitattributes` so every checkout is byte-exact, and check whether any other
  fixture-size or hash assertion depends on the same accident.

### B-010 — One H.264 test asserts a lane count the full campaign cannot guarantee

- Area: tooling
- Found while: validating backend changes with the full `video` release test run (2026-08-27).
- Observation: `h264.test.swg:49` asserts `decoder.video.avc.laneCount == 16`. The focused
  run (`--test-file h264.test.swg`) passes every time; the full module run fails the same
  assertion intermittently, with an unmodified master compiler as well as with candidate
  backends - the lane count derives from the worker pool, which the rest of the campaign is
  loading. Two backend batches lost hours to this: each read the failure as its own miscompile.
- Evidence: same command, same tree, master compiler: full run 1 did not pass, focused run 10
  passed. Candidate compiler: identical pair of outcomes.
- Next step: make the assertion machine-independent (assert against the decoder's own computed
  bound, or pin the worker count for that test), so the full campaign is deterministic.
