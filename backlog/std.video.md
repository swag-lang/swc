# Video Backlog

The module reads and writes video as a stream: a codec registered against `Video.IDecoder` and
`Video.IEncoder`, selected by extension, reading a `Core.ByteSource` and writing a `Core.ByteSink`.
It reads YUV4MPEG2, Motion JPEG in AVI or ISO-BMFF, H.264 and H.265 in ISO-BMFF or Matroska,
and MPEG-4 Part 2 in Matroska. File-backed ISO-BMFF and Matroska also expose streamed
AAC-LC tracks to std/audio, and Matroska adds AC-3, E-AC-3, DTS Core, FLAC, Layer III, Vorbis,
and Opus. Encoded payloads stay on disk;
readers retain compact per-sample indexes plus one picture, the reference frames prediction needs,
and a bounded audio queue.

The remaining work covers codec and container breadth, decoding cost, and the lifecycle of
bounded sound windows.

The picture codec of an AVI stream is the Pixel one. Its generic minimum-coded-unit walker accepts
the sampling layouts used by ffmpeg's 4:2:0, 4:2:2, and 4:4:4 Motion JPEG output.

### std.video.001 — H.264 decoding costs several times what FFmpeg does per picture

- Recorded: 2026-08-19 13:23
- Updated: 2026-09-10 21:00 — Re-measure the gap against FFmpeg after fusing dequantization into the entropy decoders, and record four rejected leads
- Intent: the decoder is byte-exact against FFmpeg on Baseline, Main, and High streams and decodes
  well above real time, but one picture still costs several times what FFmpeg spends on it. That
  margin is what a machine smaller than this one, or a stream larger than 4K, would need.
- **How this is measured, and why every earlier figure in this entry is incomparable to a new one
  (2026-09-09).** Two mistakes made the older numbers mean less than they claimed, and both are
  easy to repeat.
  - *The fixture.* A 4K clip generated through PyAV with `threads: 6` makes x264 choose sliced
    threading and write **six slices per picture**. A multi-slice picture cannot take the inline
    row-by-row path, so the parse runs on one thread while reconstruction and the loop filter run
    on another, and 43 and 55 percent of each thread's samples sit in `ntdll` waiting for the
    other. Nothing measured on such a clip describes the one-slice stream a camera or an editor
    produces. Generate with `"slices": "1", "x264opts": "sliced-threads=0"`, and count NAL units
    of type 1 and 5 per sample before trusting a fixture.
  - *The metric.* Wall time and `GetProcessTimes` are worthless here: the same binary on the same
    input reads 41 ms and 99 ms per picture minutes apart, and twenty-one interleaved A/B rounds
    of a real change gave a sign-test p of 0.66. `QueryProcessCycleTime` removes the clock rate
    but counts an idle job worker spinning beside the decode, which alone moved a run by 2.7x.
    **`QueryThreadCycleTime` on the decoding lane's own thread is the metric that works**: three
    runs in four fall within four percent. A `#test` in this module reaches the thread through
    `decoder.video.avc.frameThreads[0].thread.id`. Reading the caller thread as well is what
    proves the lane carries the whole decode: on a one-slice clip the caller costs about
    4 million cycles a picture, against 160 million for the decode.
- **Where it stands (2026-09-10, release, one AVC lane so the figure is serial, a generated
  3840x2160p25 High/CABAC one-slice clip at 18.3 Mbit/s, interleaved against FFmpeg through PyAV
  with threading disabled, four paired rounds): 98.0 million cycles per picture at the minimum
  against FFmpeg's 36.0 million, a paired ratio of 2.75 on the median (2.74 and 2.77 in the two
  quiet rounds).** In wall time, 32.4 ms against 11.8 ms. The 2026-09-09 measurement of the same
  clip read 160.7 million against 45.7 million, 3.2 to 3.6, in a different machine state: only the
  paired ratio carries from one state to another. FFmpeg's figure carries its own demuxing and the
  PyAV frame objects, so the decode-to-decode ratio is if anything slightly worse than that.
- Where that time goes, by sampling the decoding thread and resolving every sample inside
  `[rva, rva+size)` of a real function (2026-09-09, same clip): entropy parsing 50.9 percent —
  `Slice.residualCabac` alone 22.3 and `CabacReader.decision` 7.6 — motion compensation 16.3,
  the loop filter 12.8, and reconstruction 11.9. The largest single items after the two entropy
  ones are `Slice.bookkeepMb` 4.0, `Video.H264.deblockMb` 3.7, `Slice.dequant4x4` plus
  `dequant8x8` 6.4 together, `Slice.motionAt` 3.3, and `Video.H264.mcChroma` 3.2.
- **Retired lead: generic `Array` indexing is not a cost.** The 2026-09-01 sample in this entry
  read 11.3 percent in `Array.opIndexSet` and `Array.opIndexPtr`. That was an artifact of
  attributing each sample to the nearest symbol below it: the 54 small unused generic bodies the
  linker leaves scattered through `.text` act as sinks for addresses that belong to their
  neighbours. Scanning the emitted code settles it — `Slice.bookkeepMb` is 2161 bytes and makes
  exactly two direct calls, neither of them an accessor. Every `Array` index on the hot paths is
  inlined. Do not spend anything on this again.
- Four changes landed on 2026-09-09, each byte-exact against every reference fixture:
  - The per-4x4-block motion state was six picture-wide arrays — two vector components, a
    reference index, a 32-bit picture order count, and a direct flag, per list. It is now one
    eight-byte `BlockMotion` record per list, and the order count is a one-byte identity
    allocated per picture, which is all the loop filter compares. Nine cache streams became five,
    four megabytes of writes a picture disappeared, and a sixteen-byte store now publishes two
    blocks where four stores published one.
  - Dequantization cleared its output with sixteen or sixty-four scalar two-byte stores and
    re-indexed a three-dimensional scaling table at every coefficient. It now clears with
    `Memory.clear` and addresses one hoisted row.
  - Implicit bi-prediction with equal weights — which is what a symmetric B picture carries — went
    through the full weighted path, widening every sample to thirty-two bits to multiply it by one
    half. `(a * 32 + b * 32 + 32) >> 6` is `(a + b + 1) >> 1` exactly, so it now takes the rounded
    average.
  - The loop filter also recovered block coordinates from a block index with an integer division
    and a modulo, twice for every edge segment, when every caller already knows the macroblock.
- **Dequantization now happens in the entropy decoders (2026-09-10), as FFmpeg's
  `decode_cabac_residual` does it.** Each level is written at its raster position already scaled by
  its factor, so the inverse transform reads the macroblock's residual record in place: the two
  dequantization passes, their per-block clears and their zigzag scatter are gone. A DC block keeps
  its raw levels, since it goes through its own transform first. Interleaved against the previous
  build on the same clip, byte-exact: minimum −5.4 percent, median of paired rounds −4.3 percent.
- Profile after that change (2026-09-10, same clip and method): `Slice.residualCabac` 25.3 percent,
  `CabacReader.decision` 8.5, `Slice.bookkeepMb` 4.2, `Video.H264.mcChroma` 4.0,
  `Video.H264.deblockMb` 3.8, `Slice.motionAt` 3.5. The neighbor queries together —
  `motionAt`, `predictMv`, `blockNz`, `mbAvailable`, `chromaBlockNz`, `neighborIntraMode` — are
  about 8 percent.
- **The significance map keeps its arithmetic registers on the stack, and moving them to registers
  did not pay.** They live in a small local structure passed by address to an inlined decision,
  and with no memory-to-register promotion in the backend a structure whose address is taken stays
  on the stack: the emitted loop loads and stores `range` and `low` at every step of every bin,
  where FFmpeg's hand-written loop keeps them in registers. Plain locals driven through mixins do
  put them in registers — the whole bin computes in `eax` and `edx` — yet the build measured
  3.4 percent slower on the median and 3.6 percent on the minimum, byte-exact. One spill of each
  remains at the renormalization branch, and the leading-zero count is emitted as `bsr` plus
  `cmove` rather than `lzcnt`. Retry only once the allocator stops spilling at branch boundaries
  and the count is a single instruction, both of which are compiler.optimization matters.
- Next: the structural difference left with FFmpeg is its per-macroblock neighbor caches
  (`fill_decode_caches`): every context — coded-block flag, motion vector difference, reference
  index, and the loop filter's strengths through `check_mv` — is a fixed-offset read in a small
  array filled once per macroblock, where this decoder makes a call with availability and slice
  checks for every neighbor of every block. A non-zero-count cache for the coded-block-flag
  contexts is the smallest first step; the motion cache and the strengths follow from it.
- A second stream shape is worth its own measurement: a multi-slice picture takes the banded path
  and ping-pongs between two threads that each spend about half their time waiting. FFmpeg turns
  the same slices into parallelism. That is a real class of stream — every low-latency encoder
  writes it — and this decoder is at its worst on it.
- Already measured and rejected, so they do not need trying again: inlining every CABAC decision
  (register pressure regresses the parser, unlike the two significance decisions, which pay);
  branchful CABAC decisions; quotient-based bypass runs; four-byte row copies in `bookkeepMb`;
  publishing co-located motion in a parallel pass instead of on the entropy thread; a 16-bit SWAR
  six-tap (expanding byte inputs costs more than the packed arithmetic saves on this backend); and
  recasting the RGB conversion as `pmaddwd` pair sums — that last verdict predates `Core.Math.Simd`
  becoming inlinable across modules and should be re-measured before it is trusted. Also rejected
  on 2026-09-10: porting FFmpeg's CABAC engine representation, where `low` carries the bits loaded
  ahead and a marker so renormalization is a plain shift, costs 8.7 percent more on the minimum as
  written here; keeping the level loop's registers in the same address-taken structure as the
  significance map is neutral; and answering strength zero early when both blocks of an inner edge
  hold identical motion records lost every measured round.
- Current boundary: `decode/h264/deblock.swg` already packs weak filtering in both directions,
  strong horizontal luma/chroma, and strong vertical luma through a transposed tile. The remaining
  strong vertical chroma path is scalar and is tracked by cpu.simd.023. Do not implement those
  shipped filters again.
- A trap for anything that moves reconstruction away from the parse again: Intra_16x16 and chroma
  reconstruction read residual blocks the entropy decoders never parsed, so the per-macroblock
  residual record must stay cleared (see `prepareMb`).
- Complete when: the serial cost of one 3840x2160 picture is within a third of FFmpeg's on the same
  machine, measured in decoding-thread cycles on a one-slice clip.

### std.video.012 — 4:2:2 is the chroma format H.264 still refuses

- Recorded: 2026-09-09 19:33
- Intent: the decoder reads 4:2:0 and, since this change, 4:4:4, which is what a screen recorder,
  a colourist's intermediate, and x264 at `profile=high444` produce. `chroma_format_idc` equal to
  2 is what remains, and a file carrying it is refused at the sequence set rather than decoded.
- Evidence: `decode/h264/sets.swg` fails a sequence set whose `chroma_format_idc` is neither 1 nor
  3, with "video decoder only supports 4:2:0 and 4:4:4 H.264 streams". `Sps.chromaShift` states one
  halving or none, so it has no way to say "half the width and all of the height".
- Why it is not the same work as 4:4:4: a 4:4:4 colour plane is coded exactly as luma, so the
  4:4:4 path is the luma path with a plane index. 4:2:2 is a third geometry of its own — eight
  chroma blocks per plane, a 2x4 chroma DC transform with its own scan, a chroma quantizer offset
  of `+3`, and its own CABAC categories — and none of that is reached by the plane index.
- Also unresolved for both formats: separate colour planes
  (`separate_colour_plane_flag`), which codes each plane as its own monochrome picture with slice
  headers of its own, is refused with a message of its own.
- Next: decide whether a real file is asking for it. If one is, start from `Sps` carrying a
  horizontal and a vertical chroma shift rather than one, then the chroma DC transform.
- Complete when: a 4:2:2 fixture encoded by x264 decodes byte-exact against FFmpeg, beside the
  4:2:0 and 4:4:4 ones in `video/src/tests/datas`.

### std.video.010 — Decode VP9 pictures in Matroska and WebM

- Recorded: 2026-09-06 18:27
- Evidence: the Matroska demuxer already accepts the `webm` document type and retains packet
  timestamps, seek points and lacing, but has no VP9 picture decoder. Its advertised extension
  is `.mkv`. Swag Scope builds its playback selectors from `Reader.decodableFormats()`, so the
  missing implementation belongs to the video module.
- Next: integrate a bounded VP9 decoder through the existing picture/plane and seek contract,
  advertise WebM when supported, and retain the existing Opus/Vorbis audio integration.
- Complete when: redistributable VP9 fixtures decode and seek with reference plane comparisons,
  malformed input respects decoder limits, audio remains synchronized, and Scope discovers the
  supported format automatically while keeping its separate binary structure viewer.
- Historical provenance: split from the retired `app.scope.video.014` playback capability entry.
- Related: std.video.011, app.scope.binary.011

### std.video.011 — Decode AV1 pictures in Matroska and WebM

- Recorded: 2026-09-06 18:27
- Evidence: the Matroska demuxer already accepts the `webm` document type and retains packet
  timestamps, seek points and lacing, but has no AV1 picture decoder. Its advertised extension
  is `.mkv`. Swag Scope builds its playback selectors from `Reader.decodableFormats()`, so the
  missing implementation belongs to the video module.
- Next: integrate a bounded AV1 decoder through the existing picture/plane and seek contract,
  advertise WebM when supported, and retain the existing Opus/Vorbis audio integration.
- Complete when: redistributable AV1 fixtures decode and seek with reference plane comparisons,
  malformed input respects decoder limits, audio remains synchronized, and Scope discovers the
  supported format automatically while keeping its separate binary structure viewer.
- Historical provenance: split from the retired `app.scope.video.014` playback capability entry.
- Related: std.video.010, app.scope.binary.011

### std.video.005 — Reduce the measured serial cost of H.265 decoding

- Recorded: 2026-08-25 08:38
- Updated: 2026-09-06 18:10 — separated serial decoding cost from range-extension support
- Intent: the decoder is byte-exact against five JCT-VC conformance bitstreams and against x265
  output in both containers, so what it decodes it decodes correctly. What it is judged on next is
  the serial cost of one picture. Unsupported chroma/profile breadth is tracked separately in
  std.video.009.
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
  they are compiler.optimization.011's shape — twelve of them survive in one function. A luma filter call covers
  about 800 samples in 1.73 microseconds, which is 8.6 cycles a sample where the instruction
  count predicts about three.
- What that says about where the gap is, and it is not one thing:
  - **Most of the gap is this compiler, and it was measured, not inferred.** The loop filter of
    clause 8.7.2.5 written twice, statement for statement, in C and in Swag, over the same plane
    with the same decision mix: **18.3 ms a picture under clang 21 `-O2 -msse2`, 40.6 under this
    compiler in release — 2.2x**. (clang's own `-march=native` build takes 34.1 ms: its
    auto-vectorizer costs it 1.9x on this code, so a clang figure is only an answer sheet once
    you have checked which clang figure it is.) See
    [compiler.optimization.011](compiler.optimization.md#compileroptimization011--a-simd-routine-keeps-its-strides-and-counts-in-the-frame),
    which carries the instruction and frame-access counts on both sides.
  - **Where that leaves the work, in order**: closing the backend's 2.2x is worth more than
    every decoder change left in this entry put together, and it helps every module of the
    library at once. After it, the stages still written scalar — the loop filter (15.7 ms) and
    the residual add (3) — and then 256-bit forms for what is already paired through `pmaddwd`:
    motion compensation (33) and the inverse transform (8.5), which cpu.simd.002 covers.
    First backend instalment measured (2026-08-26): loop residency in the register allocator
    plus per-object frame reachability in the post-RA hoist took the serial conformance decode
    (wpp-main10 + ipred, alternated processor time of the test binary) down 3 to 7 percent, and
    the back-edge reload cause across the `video` workspace from 5060 to 242. What bounds the
    next instalment is eviction churn under real pressure — see
    [compiler.optimization.011](compiler.optimization.md#compileroptimization011--a-simd-routine-keeps-its-strides-and-counts-in-the-frame)
    and the current split-allocator boundary in
    [compiler.optimization.024](compiler.optimization.md#compileroptimization024--the-split-allocator-claims-a-whole-instruction-for-an-implicit-operand).
    These timing and spill counts predate that allocator and need a new baseline.
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
    [compiler.optimization.011](compiler.optimization.md#compileroptimization011--a-simd-routine-keeps-its-strides-and-counts-in-the-frame),
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
    cpu.simd.002, and it is worth roughly half of motion compensation and a third of the transform.
  - **The parse is not bin-bound.** One picture of the clip in std.video.001's harness decodes 1,055,000
    context bins and 288,000 bypass bins; at 27 to 44 ms that is 30 to 50 ns a bin against the
    ten or so a tuned decoder needs, and the bin itself is a short serial chain that instruction
    count barely moves (std.video.001 measured exactly that). What is left is everything around it: the
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
- The three copies left in that figure were removed on 2026-09-01: the deblocked planes now swap
  with retained scratch storage, and every coding tree block writes its destination once. The
  available local MP4 was H.264, so this change has no new trustworthy timing; the complete native
  and JIT conformance selection, including the sixty-picture MediaTek SAO stream, remains exact.
- Where the picture stands once the two passes above landed, same clip and same method
  (119 ms a picture): the coding tree walk is 94 ms of it, and inside it **coefficient parsing
  is 44**, inter prediction 19, the inverse transform 9, adding the residual 7, intra 0.4, and
  the walk's own bookkeeping 14. Outside it, deblocking is 18, sample adaptive offset 10 and the
  reduction to eight bits 4. One picture decodes **1,055,000 context bins and 288,000 bypass
  bins**, so the parse spends about 33 ns a bin — the ratio std.video.001 records for H.264, and the
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
  a vertical edge needs the transpose the H.264 filter already does. The fractional filters and
  the transform are both 128 bits wide, and this stream is the case where 256-bit forms would pay;
  and a uni-predicted block is filtered into `predBuffer` and then read again to be combined,
  where one pass could write the picture directly.
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
- Related: std.video.001

### std.video.009 — H.265 range-extension chroma formats are not decoded

- Recorded: 2026-09-06 18:10
- Evidence: `decode/hevc/sets.swg` rejects `chroma_format_idc` values other than 1 and
  bit depths other than 8 or 10. It also rejects PCM, range-extension, multilayer, 3D and screen
  content tools. Current Main/Main10 conformance coverage does not exercise those profiles.
- Next: choose a bounded range-extension profile for 4:2:2/4:4:4 input and implement its sample
  geometry and reconstruction rules. Keep unsupported extension families explicitly rejected.
- Complete when: redistributable conformance fixtures for the chosen profile match reference
  planes, malformed inputs remain bounded, and the documented limits name every unsupported tool.
- Related: std.video.005

### std.video.008 — ISO-BMFF does not expose Layer III sound tracks

- Recorded: 2026-09-06 07:51
- Evidence: `decode/mp4/mp4.swg` accepts only the MPEG-4 audio object type `0x40` in an
  `mp4a` descriptor. The `0x69` and `0x6B` Layer III variants are rejected, although std/audio
  already decodes Layer III packets and the Matroska reader exposes them.
- Next: retain the object type while reading the audio descriptor and construct the existing
  Layer III packet stream for supported variants. Add a redistributable multiplexed fixture.
- Complete when: ISO-BMFF Layer III tracks enumerate, decode, seek, and retain their timestamps
  through `Video.Reader`, with reference PCM comparisons and explicit rejection of unsupported
  MPEG audio layers.
- Related: std.audio.002

### std.video.006 — Interlaced H.264 is the last picture feature a real library asks for

- Recorded: 2026-08-25 16:27
- Updated: 2026-09-06 07:51 — git: prompt 6
- A recorded survey of 592 films of one personal library, twelve pictures each against FFmpeg:
  590 decode, and one of the two that do not is refused with `video decoder does not support
  interlaced H.264 streams`. It is a 1968 film telecined to fields.
- What it needs is field coding: `field_pic_flag`, a picture built from two fields with their own
  reference lists and their own picture order counts, and the deblocking and prediction rules that
  follow from a field being half a picture. That is a real piece of the standard rather than a
  corner of it, and nothing else in the library needs it.
- Worth knowing before starting: the same library holds no interlaced H.265 and no interlaced
  MPEG-4 Part 2, so this is one codec's feature rather than a shape the module lacks everywhere.

### std.video.007 — RealVideo RV40 is one film, and a whole codec

- Recorded: 2026-08-25 16:27
- Updated: 2026-09-06 07:51 — git: prompt 6
- The last film of the 592 that does not open is `V_REAL/RV40`, a 1999 encode. RealVideo 9/10 is an
  H.264 relative with its own slice format, its own bitstream syntax, and no relationship to
  anything this module reads.
- It is recorded because the sweep found it, not because it is worth writing: one film against a
  codec of that size is a poor trade. Transcoding that file to a supported codec is an
  alternative; changing only its container does not make the RV40 pictures decodable.
- Related: app.scope.video.015 in [app.scope.video.md](app.scope.video.md)

### std.video.002 — Refreshing a bounded sound window interrupts playback

- Recorded: 2026-08-25 22:01
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: the sixty-second Matroska sound window now rebuilds asynchronously and keeps the picture
  queue full even when an SMB scan takes 1.3 to 2.2 seconds, but every rebuild publishes a new
  `SoundFile`, so the player replaces its voice and the listener still hears the seam.
- Complete when: the packet window can grow or hand off without replacing the playing voice, and
  a long network-share playback crosses several refresh boundaries without an audio interruption.
- Constraint: `Audio.SoundFile.openPacketStream` currently takes its packet table by value and a
  voice reads it without a lock. The ownership and synchronization contract must change before a
  playing stream can observe appended packets safely.
- Related: std.video.003

### std.video.003 — Retired sound windows remain alive until the video closes

- Recorded: 2026-08-25 22:01
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: release superseded bounded `SoundFile` windows as soon as no player or decoder can still
  hold a pointer into them; today every published window stays alive until the whole file closes.
- Complete when: window ownership makes the last consumer observable, several refreshes keep only
  the active and genuinely referenced windows, and a seek cannot read freed packet storage.
- Related: std.video.002

### std.video.004 — An AVI larger than four gigabytes is refused

- Recorded: 2026-08-17 18:40
- Updated: 2026-08-30 12:44 — git: Refactor and update various components for improved functionality and clarity
- Intent: every size in the AVI container is a 32-bit field, so the encoder refuses a stream that
  would run past four gigabytes and the decoder reads only the `idx1` table. OpenDML answers both
  with 64-bit `indx` chunks and a `RIFF AVIX` continuation, which is what any capture longer than a
  few minutes at a usable bitrate produces.
- Complete when: the decoder reads the `indx` hierarchy and follows `AVIX` continuations, and the
  encoder emits them instead of failing once the stream approaches the limit.
