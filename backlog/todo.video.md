# std/video

The module reads and writes video as a stream: a codec registered against `Video.IDecoder` and
`Video.IEncoder`, selected by extension, reading a `Video.Source` and writing a `Video.Sink`.
Four picture codecs ship — YUV4MPEG2, AVI, ISO-BMFF with Motion JPEG, and ISO-BMFF with H.264 —;
file-backed ISO-BMFF also exposes streamed AAC-LC tracks to std/audio. Encoded payloads stay on
disk; readers retain compact per-sample indexes plus one picture, the reference frames H.264
prediction needs, and a bounded audio queue.

What the module competes with is ffmpeg's demuxers, and the distance is measured in formats rather
than in design: what is missing is decoders.

The picture codec of an AVI stream is the Pixel one, so what Motion JPEG this module reads is
decided there — [T-426](todo.pixel.md#t-426--jpeg-chroma-sampling-is-limited-to-one-block-per-unit)
is the layout it does not read yet.

### T-504 — H.264 decoding costs about twice what FFmpeg does per picture

- Intent: the decoder is byte-exact against FFmpeg on Baseline, Main, and High streams and now
  decodes well above real time, but it still spends about twice the processor time per picture that
  FFmpeg does. That margin is what a machine smaller than this one, or a stream larger than 4K,
  would need.
- Where it stands (2026-08-23, release, 3840x2160p25 High/CABAC, the 20.3 GB 226,479-picture
  Filmora recording, warm over 300 consecutive pictures with the machine allowed to cool between
  runs): 8.0, 9.9 and 13.4 ms per picture at the start, the middle and the end of the file, against
  12.8, 17.0 and 22.0 before this pass. Serial cost, one lane and one worker: 59.6 ms per picture —
  entropy parse 33.4, reconstruction 17.4, loop filter 8.6 — plus 13.4 for the conversion to RGB.
  FFmpeg on the same machine needs about 27 ms of processor time per picture single-threaded and
  about 3 ms of wall time frame-threaded.
- What the gap is no longer responsible for (2026-08-24, release, the same recording played in
  sFileScope at half and nine tenths of its length, sixty-second runs): the decoder is not what
  limits playback of this stream on this machine. Its run-ahead queue stayed full at ten pictures
  in every run, and handing one picture over cost 3 to 8 ms. What limited the picture rate was the
  presentation path — see F-191 in findings.gui.md — and two defects in the player, both fixed:
  the run-ahead was taken with an unstable array removal, which left eight of its ten slots holding
  pictures that would never be shown, and presentation was capped at one picture per turn of the
  application loop, which let the picture fall up to 79 frames behind the clock without anything
  reporting it. Playing the stream is therefore no longer evidence about this entry; measure the
  serial cost of one picture instead.
- The conversion to RGB has since left the decode path entirely: `Video.Reader.decodeFramePlanesInto`
  hands the reconstructed planes over as they are, `Pixel.PixelFormat.Yuv420` carries them as a
  texture, and the renderer converts where it samples. Every figure below that adds a conversion cost
  to a picture is therefore describing a path the player no longer takes.
- Measured shape of the remaining gap (2026-08-23, release, 3840x2160p25 High/CABAC, one lane and
  one worker so the figures are processor time for one picture): entropy parse 37.7 ms,
  reconstruction 19.7 ms, loop filter 9.6 ms, and 15.7 ms more for the conversion to RGB, which
  FFmpeg's 27 ms does not contain at all. Reconstruction splits into motion compensation 7.5,
  luma residual 4.1, chroma residual 3.1, intra prediction 2.5. One picture decodes 904,000 bins:
  568,603 context-coded, 310,298 through the significance-map path, 25,095 bypass. At 37.7 ms the
  parse therefore spends roughly 40 ns per bin against the few nanoseconds a tuned decoder needs,
  and that ratio, not any one stage, is the distance to FFmpeg.
- How to measure this at all (2026-08-23). Wall time on this file is worthless on its own: the same
  window read 25.8 ms per picture alone and 67.7 ms as the fourth point of a five-point sweep in one
  process, because the part measures a thermal state, not a stream. Measure one point per process
  with the machine cooled, and read processor time, which held to about ten percent across runs that
  moved wall time threefold. There is no processor-time call in `Core`; a probe can declare
  `GetProcessTimes` itself. A synchronous decode loop also reports a shape that is not a defect: a
  picture already in the reorder set costs about 2 ms and one that has to be decoded costs 100 to
  400, so the sequence looks like spikes, the spike positions are fixed by the stream and identical
  across runs, and only the mean says anything. The player never sees them, since it decodes on its
  own producer thread into a queue.
- Where the serial cost goes, measured per macroblock over the inline path (2026-08-23, release,
  3840x2160 High/CABAC, one lane; the split held to within one point between `fast-debug` and
  `release`): entropy parse 41 percent, per-macroblock bookkeeping 8, reconstruction 27, and row
  completion 22 — of which 98 percent is the loop filter, edge extension and progress publication
  together costing under one.
- What the lanes actually buy (2026-08-23, release, three quarters into the file, warm): one lane
  111 ms per picture, four 54, eight 47, eleven 24 to 27, sixteen no better than eleven. Processor
  time per picture over the same range rises from 112 ms to 200-230. Eleven lanes therefore keep
  about 8.7 of this machine's 22 threads busy and the decoder is bandwidth-bound there, not
  core-bound — which is why the two attempts below, both of which only move work onto an idle
  thread, changed nothing. Less work and less memory traffic per picture is the only direction left.
- Two more attempts measured and rejected (2026-08-23, release, three quarters into the file):
  routing single-slice pictures through the banded reconstruction path that multi-slice pictures
  already use, which is four times *worse* (195 ms per picture against 49) because a picture that
  publishes its rows only at the end stops every lane predicting from it — the inline path exists
  for that reason and this should not be tried again; and handing the loop filter of each completed
  row to `Core.Jobs`, per row and batched four and sixteen rows, which is neutral (best of three,
  warm: 21.0 to 24.9 ms against 22.6 to 23.3 with the filter inside the entropy pass) and costs
  about a tenth more processor time in scheduling.
- A fifth attempt, kept but worth much less than its instruction count suggests: hold `range` and
  `low` in locals for the length of one bin, and share renormalization between the MPS and LPS
  outcomes instead of writing it twice. The context write in between stores into the same
  structure as the arithmetic registers, so left in place they were reloaded after every step —
  the emitted code read `range` five times and wrote it three, for one bin. `CabacReader.decision`
  goes from 217 to 143 emitted instructions, a third fewer, and it is byte-exact.
  **The time barely moves**: five interleaved A/B rounds on a quiet machine give 96.4 ms against
  95.4 ms of processor time per picture, about one percent, and the native halves alone are
  93.6 against 93.9 — inside the noise. An earlier three-run reading said four percent and was
  contaminated by another agent building; do not trust an unpaired figure here.
  This is the same verdict the shift-guard elision got in
  [F-136](findings.optimization.md#f-136--a-hot-loops-loop-carried-locals-all-live-in-stack-slots):
  the bin is latency-bound on its serial chain — context byte, table load, subtract, compare,
  context store — so removing a third of its instructions buys almost nothing. The change is kept
  because it is strictly less code and less memory traffic, not because it made the decoder fast.
- The same hoisting applied to `motionAt` and `mbAvailable` — resolving the neighbor macroblock
  once instead of re-addressing it through two pointers at each of the four questions asked of
  it — measured at nothing beyond the noise floor, and is kept only because it is plainly less
  work. Do not expect the per-4x4 grid caching below to pay merely because it removes accesses.
- What the emitted code says is left, and it is not a source shape:
  [F-190](findings.optimization.md#f-190--a-short-branching-function-spills-with-the-whole-register-file-free).
  After the hoisting the bin still opens with seven callee-saved pushes and a 160-byte frame, and
  still spills three values across its one branch with sixteen integer registers available. At
  roughly 568,000 context-coded bins per picture that prologue alone is about nine million
  instructions. The parse will not approach FFmpeg's until the register allocator stops doing
  this, so the entropy half of this entry is now waiting on that work rather than on another
  attempt here.
- Measuring this at all, in the shape that worked: a `#test` in the module that opens the real
  recording, decodes twenty pictures to warm the lanes and the file cache, then decodes 250 more
  and reports `GetProcessTimes` divided by the count. Jobs are synchronous in a test process, so
  `laneCount` is one and the figure is serial cost, which is what every change here targets.
  Wall time equals processor time there, and both are worthless while another agent builds: one
  contended run read 128 ms against a 90 ms baseline. Alternate the two variants in one session
  and compare means, never a single pair.
- Four attempts on that parse were measured and rejected, each byte-exact and each neutral or
  slightly worse (processor time per picture, best of three alternating runs on a quiet machine,
  74.6 ms for the unmodified decoder):
  copying the picture geometry onto the slice so neighbor lookups stop reaching through the active
  sequence set twice per access (74.6 -> 74.4, neutral); resolving the left and top neighbors once
  per macroblock instead of at each of the roughly 295,000 queries a picture makes — 115,206
  through `motionAt` and 179,988 through `mbAvailable` — which measured 6% *worse* because the
  eager resolution is paid by every skipped macroblock too (74.6 -> 81.3); making the generic
  CABAC decision branchless with the mask select the significance-map decision already uses, with
  `Swag.PrintMicro` confirming the fifty-fifty branch left the emitted code (74.6 -> 77.4); and
  holding the two arithmetic registers in locals across a complete residual block, levels and
  bypass included, which is the technique that pays for the significance map (74.6 -> 76.3).
  The cost is therefore not redundant work at the call sites and not misprediction: it is what
  each individual operation compiles to. The next attempt should start from the emitted code of
  one bin rather than from the source.
- The remaining serial cost is the entropy parse, and more than half of it is not the coefficients:
  the residual decoder is about 15 ms and the prediction, motion and bookkeeping around it about
  18. Both read and write the picture-wide per-4x4-block grids — motion, reference indices,
  differences, nonzero counts — one scattered access at a time. FFmpeg reads its neighbors once per
  macroblock into a small cache and works from that. That is the next lever, and the largest one
  left.
- After it, in expected order of value: packed strong and vertical deblocking (the transpose is the
  hard half), a profitable packed inverse-transform strategy, and a true byte-run significance
  decoder beyond the targeted inlining already in place.
- Already measured and rejected, so they do not need trying again: inlining every CABAC decision
  (register pressure regresses the parser, unlike the two significance decisions, which pay);
  branchful CABAC decisions; quotient-based bypass runs; four-byte row copies in `bookkeepMb`;
  publishing co-located motion in a parallel pass instead of on the entropy thread; a 16-bit SWAR
  six-tap (expanding byte inputs costs more than the packed arithmetic saves on this backend); and
  recasting the RGB conversion as `pmaddwd` pair sums — that last verdict predates `Core.Math.Simd`
  becoming inlinable across modules and should be re-measured before it is trusted.
- A trap for anything that moves reconstruction away from the parse again: Intra_16x16 and chroma
  reconstruction read residual blocks the entropy decoders never parsed, so the per-macroblock
  residual record must stay cleared (see `prepareMb`).
- Complete when: the serial cost of one 3840x2160 picture is within a third of FFmpeg's on the same
  machine.

### T-424 — AVI video carries no sound

- Intent: ISO-BMFF now reports AAC-LC tracks to `std/audio`, streams their access units through an
  independent cursor, and exposes exact picture timestamps for an audio-master player. AVI still
  skips the PCM stream it already declares.
- Complete when: AVI exposes its audio streams through the same reader contract instead of staying
  silent.
- Related: T-420

### T-425 — An AVI larger than four gigabytes is refused

- Intent: every size in the AVI container is a 32-bit field, so the encoder refuses a stream that
  would run past four gigabytes and the decoder reads only the `idx1` table. OpenDML answers both
  with 64-bit `indx` chunks and a `RIFF AVIX` continuation, which is what any capture longer than a
  few minutes at a usable bitrate produces.
- Complete when: the decoder reads the `indx` hierarchy and follows `AVIX` continuations, and the
  encoder emits them instead of failing once the stream approaches the limit.
