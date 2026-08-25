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

### T-425 — An AVI larger than four gigabytes is refused

- Intent: every size in the AVI container is a 32-bit field, so the encoder refuses a stream that
  would run past four gigabytes and the decoder reads only the `idx1` table. OpenDML answers both
  with 64-bit `indx` chunks and a `RIFF AVIX` continuation, which is what any capture longer than a
  few minutes at a usable bitrate produces.
- Complete when: the decoder reads the `indx` hierarchy and follows `AVIX` continuations, and the
  encoder emits them instead of failing once the stream approaches the limit.

### T-563 — H.265 reads 4:2:0 alone, and nothing has measured what it costs

- Intent: the decoder is byte-exact against five JCT-VC conformance bitstreams and against x265
  output in both containers, so what it decodes it decodes correctly. Two things are unknown or
  absent, and both are what a real library is judged on next.
- What it refuses, and where: `sets.swg` fails a sequence parameter set whose `chroma_format_idc`
  is not 1, whose bit depth is neither 8 nor 10, that enables pulse code modulation blocks, or that
  carries the range extension, multilayer, 3D or screen content tools. The 4:2:2 and 4:4:4 formats
  and the range extension are what a capture or mastering file uses; a delivery file does not.
- What is unmeasured: no figure exists for the processor time of one H.265 picture, on any stream,
  next to anything. T-504 measured H.264 that way and the measurement is what found every gain
  since; the same harness applies here unchanged, and the entropy decode is the same shape.
- Measured on a real stream (2026-08-25): the opening predictive sequence of a 3840x2076,
  23.976-fps Main10 Matroska stream took 165-185 ms per displayed picture in a quiet release run;
  140-160 ms was HEVC reconstruction. Identity weighted integer predictions were still taking the
  generic gather/interpolate/combine path. Direct copy/rounded-average prediction, row-banded
  deblocking and packed 10-to-8-bit output reduced the same sequence to 23-25 ms per picture. This
  measures that sequence only; fractional motion and frame-level parallelism remain unmeasured.
- Next step: measure before optimizing and before widening. One 1080p and one 4K stream, serial,
  one lane and one worker, processor time per picture and the stage split, against FFmpeg on the
  same machine — that figure decides whether this entry is about speed or about formats.
- Related: T-504

### T-565 — MPEG-4 Part 2 in Matroska is delivered; the AVI files are not

- Delivered 2026-08-25. The decoder reads I, P and B video object planes, half-sample motion, four
  motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, video packets, and
  both the H.263 and MPEG quantisers. Matroska reads it under `V_MPEG4/ISO/ASP` and under
  `V_MS/VFW/FOURCC`, where a bitmap header names the codec by four characters.
- Measured against FFmpeg: the two 96x64 fixtures decode to a mean absolute difference of 0.069 and
  0.028 with no sample off by more than 2, and all seventeen MPEG-4 Part 2 Matroska files of the
  library measured below decode their first forty pictures at a mean of at most 0.053 with no
  sample off by more than 3 — six of them bit for bit. What remains is the inverse transform, which
  clause A.1 does not state bit-exactly, so two conforming decoders drift along a chain of
  predicted pictures. One 720x272 file was checked to 120 pictures: mean 0.045, worst 4.
- The tables came from `OxideAV/oxideav-mpeg4video` under the MIT licence, checked entry for entry
  as `bin/THIRDPARTY.md` records. Tables B.19 to B.22, which bound a coefficient's level and run,
  were not copied at all: they are derivable from the coefficient tables, and a test rebuilds all
  four and requires them to agree, which corroborates the coefficient tables independently.
- Two things a real file needed that the specification alone does not lead to, both found by
  decoding one and comparing every sample:
  - A stream muxed from a format that states no decoding order **packs**: one sample carries a
    predicted plane and the bidirectional plane shown before it, and a plane that codes nothing
    pads the sample that plane would have taken. Display order therefore has to come from the clock
    the stream states, not from container timestamps, which are stored in decoding order there.
  - In a bidirectional plane the forward and backward vector predictors start over **at every row
    of macroblocks**, not only at the plane and at each video packet. Getting this wrong costs no
    bits, so nothing desynchronises and the pictures are merely, quietly, slightly wrong.
- The six AVI files of the twenty-three were delivered the same day through T-566; one of those is
  refused for a reason that has nothing to do with this codec, so twenty-two of twenty-three now
  decode.
- Also still open: a container whose picture codec is unsupported could expose its sound tracks
  instead of failing to open. That is what the one RealVideo file and the twenty-two DTS tracks
  need.
- Measured, not guessed (2026-08-25, 592 films of one personal library, header probe only):
  H.264 531, H.265 37, **MPEG-4 Part 2 23**, RealVideo 1. On the sound side, AC-3 659, AAC 296,
  E-AC-3 53, DTS 22, Layer III 21, FLAC 2, Vorbis 2, TrueHD 2.
- Related: T-562, T-566

### T-566 — AVI reads MPEG-4 Part 2; one file of the library still needs OpenDML

- Delivered 2026-08-25, the same day the Matroska side was. The AVI reader drives the same picture
  decoder the other containers do, names the codec through the four characters of its bitmap
  header, reads the setup headers from the front of the first frame because AVI states none of its
  own, and takes clean decode points from the `AVIIF_KEYFRAME` flag of the index. The mapping from
  four characters to a picture codec is shared with Matroska in `decode/videoforwindows.swg`
  rather than repeated.
- `ffmpeg-mpeg4-packed.avi` is the fixture: the same 96x64, 60-picture content as the other MPEG-4
  fixtures, muxed into AVI so that packing, in-stream setup headers, and the index are all read.
  It decodes at a mean absolute difference of 0.053 with no sample off by more than 2.
- Of the six AVI files of the library measured in T-565, five decode — one of them bit for bit over
  forty pictures, the rest at a mean of at most 0.0024. The sixth is refused before any picture is
  read, with `AVI chunk runs past the end of the stream`: it is an OpenDML file of 1.16 GB with no
  `idx1`, which is T-425 rather than anything to do with this codec.

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
- Related: T-565

### F-198 — A differential harness must line pictures up by time, not by rank

- Found while measuring the library: FFmpeg numbers the pictures it emits densely, and this reader
  numbers them the way the container does. The two disagree wherever a container holds a sample
  that produces no picture — a plane that codes nothing, a leading picture a random access point
  says to skip, an access unit before the first one that can be reconstructed.
- Neither numbering is wrong. A player seeks by the frame number its container states, so this
  reader answers every one of them, and a rank whose picture cannot or must not be shown is
  answered by the next one that can. FFmpeg hands out packets and frames with timestamps, so it
  drops them instead.
- Consequence for measurement: comparing picture `k` against FFmpeg's picture `k` reports a defect
  where there is none. Two files of the library did exactly that, and both proved bit-exact once
  their pictures were lined up by presentation time. A harness that compares against FFmpeg has to
  record the timestamp of each reference picture and ask this reader for the rank that carries it.
