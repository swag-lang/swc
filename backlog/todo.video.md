# std/video

The module reads and writes video as a stream: a codec registered against `Video.IDecoder` and
`Video.IEncoder`, selected by extension, reading a `Video.Source` and writing a `Video.Sink`.
Seven picture codecs ship — YUV4MPEG2, AVI, ISO-BMFF with Motion JPEG, ISO-BMFF with H.264 or
H.265, and Matroska with H.264, H.265, or MPEG-4 Part 2. File-backed ISO-BMFF and Matroska also expose streamed
AAC-LC tracks to std/audio, and Matroska adds AC-3, E-AC-3, FLAC and Layer III. Encoded payloads stay on disk;
readers retain compact per-sample indexes plus one picture, the reference frames prediction needs,
and a bounded audio queue.

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
- The mix depends on the stream, and one class of stream is not entropy-bound at all (2026-08-24,
  release, a 2496x1440 High/CABAC screen recording, one AVC lane so the figure is serial).
  Measured by disabling one stage at a time rather than by timing each: motion compensation is 44
  percent of a picture, the loop filter 10, and the whole entropy parse plus per-macroblock
  bookkeeping the remaining 46. Most macroblocks are skipped, and a skipped macroblock still costs
  a full 16x16 luma and two 8x8 chroma predictions. A per-macroblock timer cannot see this: on
  this machine `Time.monotonicTicks` costs enough that three calls per macroblock quadruple the
  decode, which is how the first attempt read its own overhead back as the answer.
- What that mix bought when the compiler was fixed rather than the decoder (2026-08-24): 10.1 ->
  8.5 ms of processor time per picture on that recording, the minimum of five interleaved pairs,
  every pair in the same direction. Four backend changes, none of them specific to video:
  mem2reg was blind to the 128-bit vector load and store, so one `#simd` temporary made the whole
  function unpromotable and every intermediate vector, stride and trip count round-tripped
  through the frame; post-RA loop hoisting treated a store through a program pointer as able to
  alias the frame, which it cannot when no address into the frame exists; the frame register is
  no longer set up in a function that names none and whose stack shape the unwind codes already
  describe; and `@bitcountlz`/`@bitcounttz` no longer branch. See
  [F-193](findings.optimization.md#f-193--a-simd-routine-keeps-its-strides-and-counts-in-the-frame)
  for what the same dumps say is left.
- Do not repeat this measurement of the call cost: marking `CabacReader.decision` `#[Swag.Inline]`
  reads as a 32 percent gain under a harness that lets the AVC lanes run, and as nothing at all
  (1.02) once the decode is serial. The first figure was the lanes rebalancing, not the call
  overhead disappearing.
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

### T-569 — Refreshing a bounded sound window interrupts playback

- Intent: the sixty-second Matroska sound window now rebuilds asynchronously and keeps the picture
  queue full even when an SMB scan takes 1.3 to 2.2 seconds, but every rebuild publishes a new
  `SoundFile`, so the player replaces its voice and the listener still hears the seam.
- Complete when: the packet window can grow or hand off without replacing the playing voice, and
  a long network-share playback crosses several refresh boundaries without an audio interruption.
- Constraint: `Audio.SoundFile.openPacketStream` currently takes its packet table by value and a
  voice reads it without a lock. The ownership and synchronization contract must change before a
  playing stream can observe appended packets safely.
- Related: T-570

### T-570 — Retired sound windows remain alive until the video closes

- Intent: release superseded bounded `SoundFile` windows as soon as no player or decoder can still
  hold a pointer into them; today every published window stays alive until the whole file closes.
- Complete when: window ownership makes the last consumer observable, several refreshes keep only
  the active and genuinely referenced windows, and a seek cannot read freed packet storage.
- Related: T-569

### T-425 — An AVI larger than four gigabytes is refused

- Intent: every size in the AVI container is a 32-bit field, so the encoder refuses a stream that
  would run past four gigabytes and the decoder reads only the `idx1` table. OpenDML answers both
  with 64-bit `indx` chunks and a `RIFF AVIX` continuation, which is what any capture longer than a
  few minutes at a usable bitrate produces.
- Complete when: the decoder reads the `indx` hierarchy and follows `AVIX` continuations, and the
  encoder emits them instead of failing once the stream approaches the limit.

### T-563 — H.265 costs three times what FFmpeg does per picture, and reads 4:2:0 alone

- Intent: the decoder is byte-exact against five JCT-VC conformance bitstreams and against x265
  output in both containers, so what it decodes it decodes correctly. What it is judged on next is
  what one picture costs and what chroma formats it refuses.
- **Measured cost of one picture, and the reference measured the same way (2026-08-26, release,
  one lane so the figure is serial processor time, on the 8.5 GB 3840x2076 23.976-fps Main10
  film, sixty pictures from twenty minutes in): 92 ms against FFmpeg's 28.6 ms of processor
  time single-threaded on the same passage of the same file. The gap is 3.2x, not the 2.1x this
  entry recorded** — that comparison put our 142 ms against a 66 ms figure measured another way.
  Both figures here decode to planes and convert nothing: ours through the module's `#test`
  harness, FFmpeg through PyAV with `thread_type` set to none.
- Where that time goes, timed into one counter per stage on that film (the sum falls short of
  the whole because what is left is the entropy parse and the walk itself): motion compensation
  33 — luma interpolation 16, chroma 7, combining the two lists 10 — deblocking 15, the inverse
  transform 8.5, the reduction to eight bits 3.2, adding the residual 3, intra 2.4, and **sample
  adaptive offset nothing at all: this film never enables it**. The parse and the per-block
  bookkeeping are therefore about 27 ms, which is on its own what FFmpeg spends on the whole
  picture. Interpolation and combining are timed per prediction block, so a few milliseconds of
  those three figures is the clock being read rather than work being done.
- What the parse gave up once it was timed rather than guessed at (2026-08-26): its prologue
  cost **8.8 ms of a picture for 4,446 transform units, two microseconds each**, and almost all
  of it was one loop. A block states the position of its last significant coefficient, and
  everything read afterwards is indexed by scan order, so the parse walked the scan backwards
  from the end of the block until the position matched — up to a thousand steps on a 32x32
  block. A scan is a permutation; its inverse answers outright. **8.8 ms became 0.8**, and one
  picture of the film fell from 98.7 ms to 83.6.
- What the emitted code says about the interpolation loops, which is where the next big number
  is (2026-08-26, `#[Swag.PrintMicro]` on `interpolateLuma`): the filter reads its tap vectors
  from a table indexed by the fraction **inside** the loop, which costs an address computation
  per pair per group of eight samples, and the accumulators **spill to the frame and are
  reloaded inside the innermost body**. Reading the taps once per block took the table
  addressing out (20 pointer loads to 5, 105 multiplies to 85) and is kept for that, but **it
  did not move the clock**: the loop is not bound by those instructions. The spills are, and
  they are F-193's shape — twelve of them survive in one function. A luma filter call covers
  about 800 samples in 1.73 microseconds, which is 8.6 cycles a sample where the instruction
  count predicts about three.
- What that says about where the gap is, and it is not one thing:
  - **Most of the gap is this compiler, and it was measured, not inferred.** The loop filter of
    clause 8.7.2.5 written twice, statement for statement, in C and in Swag, over the same plane
    with the same decision mix: **18.3 ms a picture under clang 21 `-O2 -msse2`, 40.6 under this
    compiler in release — 2.2x**. (clang's own `-march=native` build takes 34.1 ms: its
    auto-vectorizer costs it 1.9x on this code, so a clang figure is only an answer sheet once
    you have checked which clang figure it is.) See
    [F-193](findings.optimization.md#f-193--a-simd-routine-keeps-its-strides-and-counts-in-the-frame),
    which carries the instruction and frame-access counts on both sides.
  - **Where that leaves the work, in order**: closing the backend's 2.2x is worth more than
    every decoder change left in this entry put together, and it helps every module of the
    library at once. After it, the stages still written scalar — the loop filter (15.7 ms) and
    the residual add (3) — and then 256-bit forms for what is already paired through `pmaddwd`:
    motion compensation (33) and the inverse transform (8.5), which T-506 covers.
    First backend instalment measured (2026-08-26): loop residency in the register allocator
    plus per-object frame reachability in the post-RA hoist took the serial conformance decode
    (wpp-main10 + ipred, alternated processor time of the test binary) down 3 to 7 percent, and
    the back-edge reload cause across the `video` workspace from 5060 to 242. What bounds the
    next instalment is eviction churn under real pressure — see
    [F-193](findings.optimization.md#f-193--a-simd-routine-keeps-its-strides-and-counts-in-the-frame)
    and the residency notes under
    [F-195](findings.optimization.md#f-195--a-loop-header-drops-every-mapping-and-the-register-to-fix-it-is-already-spoken-for).
    Second instalment (2026-08-26 evening), measured on a C twin of the scalar loop filter
    compiled by clang-cl 20 at `/O2`, same checksum on both sides: the early-return decision
    path alone ran **2.5x** behind clang, and it decomposes into the per-call prologue of the
    uninlined filter (forcing `#[Swag.Inline]` took the gap from 2.4x to 1.75x — clang inlines
    it as a single-call-site function, which sema does not yet consider) and the displacement
    products (copy + 64-bit `imul` by ±2..4, spilled per reuse, where clang emits one `lea`).
    Multiply-by-{2,3,5,9} and their negations now rewrite to address computations, and a
    pre-allocation sink moves pure single-use definitions down to their consumer; together they
    take the same-breath probe ratio from 2.53x to 2.25x. The single-call-site inlining rule is
    the next largest lever this measurement names.
  - **What the emitted code spends on the frame is worth removing anyway.**
    `filterLumaEdge` emits 776 instructions with 171 frame accesses, `interpolateLuma` spills
    its accumulators inside the innermost body, and both run at roughly a third of the
    instructions per cycle their instruction counts predict. See
    [F-193](findings.optimization.md#f-193--a-simd-routine-keeps-its-strides-and-counts-in-the-frame),
    which now carries these numbers. This is the first lever, ahead of the two below.
  - **Deblocking is bound by the memory it touches, not by the instructions it runs.** Filtering
    the four lines of a horizontal edge in lanes rather than one at a time took 7.5 ms to 6.5.
    A second attempt let generic functions inline across source ASTs and temporarily took fifteen
    `Math.clamp` calls and forty frame accesses out of every segment (776 instructions to 688,
    171 frame accesses to 130), but changed 15.3 ms to 15.7, which is noise; it was reverted
    because those generic bodies are not safely rebound in the caller yet and miscompiled vector
    arithmetic in the `aoc2019` smoke test. A segment costs about 600 cycles and touches six to
    eight cache lines spread over as many rows; the picture's luma plane is 8 MB and the filter
    walks it twice, once per direction. What would change that is filtering both directions
    inside one band of coding tree units while its samples are still hot, which is how the
    standard's one-unit delay is meant to be used, rather than two passes over the picture.
  - **The sample work is at the ceiling of 128-bit vectors.** The interpolation filters already
    pair their taps through `pmaddwd`, and 16 ms for 15.7 million bi-predicted luma samples is
    about what that instruction count costs. FFmpeg runs the same filters 256 bits wide. This is
    T-506, and it is worth roughly half of motion compensation and a third of the transform.
  - **The parse is not bin-bound.** One picture of the clip in T-504's harness decodes 1,055,000
    context bins and 288,000 bypass bins; at 27 to 44 ms that is 30 to 50 ns a bin against the
    ten or so a tuned decoder needs, and the bin itself is a short serial chain that instruction
    count barely moves (T-504 measured exactly that). What is left is everything around it: the
    context derivations, the scan bookkeeping and the coefficient store. Deriving the
    significance context once a sub-block instead of once a coefficient took 2 ms off 44; there
    is more of that shape in `residualCoding`.
  - **Deblocking is dominated by what it decides, not by what it filters.** Filtering the four
    lines of a horizontal luma edge in lanes rather than one at a time took the horizontal half
    from about 7.5 ms to 6.5. The remaining 15 ms across both directions is half a million luma
    segments and a quarter of a million chroma ones, each deriving its own thresholds from the
    quantization parameters and tables before it touches a sample. A chroma segment is two lines
    of four samples and its derivation is longer than its filter.
- Where that time went before this pass, measured by disabling one stage at a time rather than by timing each
  (before the pass below; the sum of the parts exceeds the whole because disabling one stage
  changes what the next one reads): motion compensation 47, the loop filter 37, the inverse
  transform 34, adding the residual 14, the reduction to eight bits 10, intra prediction 5, sample
  adaptive offset 5, and the entropy parse and per-block bookkeeping the remaining 12.
- What the stream asks for, counted per picture rather than guessed: **15.7 million luma samples
  and 8.0 million chroma samples go through fractional interpolation** — the whole picture,
  bi-predicted — against 0.6 million taken at an integer position. **8.0 million samples pass
  through a 32x32 inverse transform**, 0.8 million through a 16x16, and 1.1 million of those are
  a DC coefficient alone. A low-bitrate 4K stream is therefore not entropy-bound at all: it is
  sample work from end to end.
- What this pass changed (2026-08-25), all byte-exact against the conformance digests:
  - The loop filter addressed every sample by recomputing `(y + padding) * stride + (x + padding)`
    and re-testing the edge direction, about seventy times per four-line segment and half a million
    segments a picture. It now resolves one base pointer and two steps per segment, one that walks
    the edge and one that crosses it. **37 -> 19 ms.**
  - Motion compensation gathered a reference block into scratch whenever its window left the
    picture, although a finished reference already repeats its edges through eighty samples of
    padding, which is exactly what the clamp of clause 8.5.3.3.3 produces. Reading the padded plane
    where it lies leaves 24 gathers a picture instead of thousands.
  - Edge replication wrote its eighty samples one at a time; it fills whole vectors now.
  - The frame lanes ran at normal priority while the H.264 ones run below it, so a decoder that is
    deliberately ahead of the clock competed with the thread that has to present on it.
- What the pass of 2026-08-26 changed in the 16x16 and 32x32 inverse transform, byte-exact
  against the conformance digests and against a hash of the film's own planes. **The two matrix
  passes are about twice as fast** — about 12 ms of a 3840x2076 Main10 picture instead of about 24, the
  ratio read as 1.9 to 2.1 over three runs of 625,000 real transform blocks each. Three changes,
  of which the first is most of it:
  - Both passes pair two basis functions into one `pmaddwd`. Every value they multiply is already
    clamped into sixteen bits, so a matrix row interleaved with the next one meets the two
    coefficients that go with them, and one multiply-add covers eight products where a widened
    multiply covered four. This is what the interpolation filters had been doing all along. It
    also retires the special case that read the last group of a 32-wide row from the row above
    it, since a group of eight now divides a row of thirty-two. **1.52x on its own.**
  - The second pass wrote its results by converting each vector to a four-element array and
    storing the lanes one at a time, into a destination that is contiguous. The vectors are
    stored where they stand. **1.34x on top of the pairing.**
  - The buffer between the passes now holds one column of the block per row. The first pass fills
    eight consecutive samples of one column, so its stores are vectors too, and the second pass
    reads one sample per basis, for which the stride costs nothing. **Neutral in time** (1.00 and
    1.03 against the strided form, measured against each other), kept because it is less code and
    no longer round-trips a vector through the frame.
- What one picture actually spends per stage, measured 2026-08-26 in one run by timing each
  stage into its own counter rather than by disabling it, on a fifteen-second 3840x2076 Main10
  clip (236 ms a picture at the time): **sample adaptive offset 90 ms**, deblocking 18, the
  inverse transform 13, adding the residual 9, combining predictions 7, integer-position
  prediction 10, chroma interpolation 10, the reduction to eight bits 4, intra 0.5, and the
  entropy parse and bookkeeping the rest. The recorded profile above puts sample adaptive offset
  at 5 ms, which is what disabling one stage at a time said; timing it says it was the largest
  stage in the decoder. **Prefer a counter per stage to a stage switched off** — a switch also
  removes the work every later stage does on what it wrote, and here it hid a factor of eighteen.
  Two figures in that list are mostly probe: interpolation is timed per prediction block, and a
  4x4 chroma block costs less than the two clock reads around it.
- What the sample adaptive offset pass of 2026-08-26 changed, byte-exact against the conformance
  digests, which include the MediaTek sample adaptive offset stream, and against a hash of the
  clip's own planes. **90 ms a picture became 30, and the whole picture went from 186 to 137**
  (four interleaved runs each, no overlap between the two sets). The edge offset filter tested
  four picture boundaries and recomputed three addresses for every sample of the picture, the
  same shape the loop filter was fixed for the day before. The block is now trimmed once to
  where both neighbours exist, each row resolves three line bases, and eight samples are
  filtered at a time: a comparison already answers with a lane of ones, so the sign of a
  difference is the difference of two comparisons, and the offset is selected by category
  instead of looked up.
- What the same treatment did to the band offset path, half an hour later and byte-exact the
  same way: **18 ms a picture became 3.4**. Its four bands are consecutive, so where a sample
  falls is its distance from the first band rather than an entry of a table of thirty-two, and
  the four selections that serve an edge category serve it unchanged. Sample adaptive offset now
  costs about 10 ms of a picture, of which 3.3 is the three plane copies: **90 ms became 10**.
- Where the picture stands once the two passes above landed, same clip and same method
  (119 ms a picture): the coding tree walk is 94 ms of it, and inside it **coefficient parsing
  is 44**, inter prediction 19, the inverse transform 9, adding the residual 7, intra 0.4, and
  the walk's own bookkeeping 14. Outside it, deblocking is 18, sample adaptive offset 10 and the
  reduction to eight bits 4. One picture decodes **1,055,000 context bins and 288,000 bypass
  bins**, so the parse spends about 33 ns a bin — the ratio T-504 records for H.264, and the
  same conclusion: the bin itself is a short serial chain that instruction count barely moves.
- What the parse gave up anyway (2026-08-26): the `sig_coeff_flag` context was derived per
  coefficient although only the position inside the sub-block varies — which neighbouring
  sub-blocks are coded selects one of four patterns, and everything else adds a constant. Both
  are answered once per sub-block now, and a coefficient reads one byte of a table and adds it.
  609,000 derivations a picture become 609,000 lookups: **44 ms becomes 42**, three interleaved
  runs each with no overlap. Small, and kept for being less work rather than for the figure.
- Next, in expected order of value: **deblocking is the largest stage left that is not the
  entropy parse**, 18 ms a picture and entirely scalar — it filters four lines at a time and
  the four lines of a horizontal edge are four consecutive columns, so they load as one vector;
  a vertical edge needs the transpose the H.264 filter already does. What is left of sample
  adaptive offset is three full-plane copies, which exist so that a block never reads what an
  earlier one wrote and could be a swap of two buffers instead; the
  fractional filters and the transform are both 128 bits wide, and this stream is the case where
  256-bit forms would pay; and a uni-predicted block is filtered into `predBuffer` and then read
  again to be combined, where one pass could write the picture directly.
- What it refuses, and where: `sets.swg` fails a sequence parameter set whose `chroma_format_idc`
  is not 1, whose bit depth is neither 8 nor 10, that enables pulse code modulation blocks, or that
  carries the range extension, multilayer, 3D or screen content tools. The 4:2:2 and 4:4:4 formats
  and the range extension are what a capture or mastering file uses; a delivery file does not.
- What to measure it on: a fifteen-second 3840x2076 Main10 encode of the film carries the same
  mix and sits beside the work, which the film itself does not — it lives on a drive that
  is not always mounted, and twenty gigabytes of it never enter a measurement anyway.
- How to measure it: a `#test` in the module that opens that clip, decodes twenty pictures to
  warm the file cache and the reference set, then decodes thirty more and reports `GetProcessTimes`
  divided by the count. Jobs are synchronous in a test process, so the lane count is one and the
  figure is serial cost. Wall time on this machine is worthless on its own — the same window reads
  7 ms and 25 ms for the same work depending on how warm the package is.
- Two traps this measurement fell into, both of which produced confident and opposite verdicts
  (2026-08-26). **Every decode must walk forward.** Asking for a picture behind the one just
  produced makes the reader seek to a key picture and decode its way back, so a harness that
  re-warmed each round from the same start charged sixteen catch-up pictures to the measured
  window: the same build read 240 ms per picture over ten pictures and 135 over sixty, and the
  A/B changed sign with the count. And **the whole-picture figure cannot settle a stage worth a
  few percent on this machine**: eight interleaved runs of the same pair of binaries put the
  minimum one way and the median the other. What settles it is an intra-process A/B — build both
  implementations into one binary, run them on the same block with the order alternating so cache
  warmth favours neither, and accumulate `Time.monotonicTicks` into one counter each. One run of
  the film then reads the stage directly, with no machine drift in it.
- Complete when: the serial cost of one 3840x2076 Main10 picture is within a third of FFmpeg's on
  the same machine.
- Related: T-504

### T-567 — Interlaced H.264 is the last picture feature a real library asks for

- Measured 2025-08-25 over 592 films of one personal library, twelve pictures each against FFmpeg:
  590 decode, and one of the two that do not is refused with `video decoder does not support
  interlaced H.264 streams`. It is a 1968 film telecined to fields.
- What it needs is field coding: `field_pic_flag`, a picture built from two fields with their own
  reference lists and their own picture order counts, and the deblocking and prediction rules that
  follow from a field being half a picture. That is a real piece of the standard rather than a
  corner of it, and nothing else in the library needs it.
- Worth knowing before starting: the same library holds no interlaced H.265 and no interlaced
  MPEG-4 Part 2, so this is one codec's feature rather than a shape the module lacks everywhere.

### T-568 — RealVideo RV40 is one film, and a whole codec

- The last film of the 592 that does not open is `V_REAL/RV40`, a 1999 encode. RealVideo 9/10 is an
  H.264 relative with its own slice format, its own bitstream syntax, and no relationship to
  anything this module reads.
- It is recorded because the sweep found it, not because it is worth writing: one film against a
  codec of that size is a poor trade, and remuxing that one file is the cheaper answer.
- Related: T-571 in [todo.filescope.md](todo.filescope.md)
