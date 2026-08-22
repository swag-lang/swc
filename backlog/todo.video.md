# std/video

The module reads and writes silent video as a stream: a codec registered against `Video.IDecoder`
and `Video.IEncoder`, selected by extension, reading a `Video.Source` and writing a `Video.Sink`.
Four codecs ship — YUV4MPEG2, AVI, ISO-BMFF with Motion JPEG, and ISO-BMFF with H.264 — and the
readers hold one frame of memory whatever the length of the file, plus the reference frames H.264
prediction needs.

What the module competes with is ffmpeg's demuxers, and the distance is measured in formats rather
than in design: what is missing is decoders.

The picture codec of an AVI stream is the Pixel one, so what Motion JPEG this module reads is
decided there — [T-426](todo.pixel.md#t-426--jpeg-chroma-sampling-is-limited-to-one-block-per-unit)
is the layout it does not read yet.

### T-504 — H.264 decoding runs below real time at high resolutions

- Intent: the decoder is byte-exact against FFmpeg on Baseline, Main, and High streams, but every
  stage is scalar Swag. The 2026-08-19 pass took a 1080p30 Main stream from 9.3 to about 16
  frames per second in release, byte-identical: branchless sign-bit clamps on every per-sample
  path (F-165), pair-wise YUV-to-RGB conversion, word-wide plane copies and rounding-up SWAR
  averages, chroma zero-phase and one-axis fast paths, one derivation and one job per quadrant
  under 8x8 inference plus a 16x16 merge for uniform direct and skip macroblocks, a uniform-MB
  strength shortcut in deblocking, average-fused interpolation passes, memset-based `prepareMb`,
  and a word-buffered branchless CABAC engine. The sFileScope player bounds its catch-up work per
  tick, so a slow stream plays smoothly below real time instead of freezing, but it should not
  have to. A follow-up split entropy parsing from reconstruction, fans independent inter
  macroblock bands and YUV-to-RGB bands through `Core.Jobs`, and makes forward seeks restart at
  a nearer sync sample. On Intel's 300-frame 1080p sample this reduced a release decode from
  about 17.5 s to 14.8 s; seeking directly to its last frame dropped from decoding the whole
  stream to about 1.25 s because the decoder starts at sample 270. Wavefront deblocking then
  halved that stage on Intel's 556-frame 1080p sample (about 5.7 s to 2.5 s), bringing the full
  release decode to about 19.6 s for a 23.2 s clip. Seeking skips non-reference pictures on POC
  type 0 streams; the last-frame seek on that sample fell from about 5.5 s to 3.3 s by omitting
  69 of the 162 intervening pictures. sFileScope also stopped recreating its 1080p renderer
  texture per frame and decodes a timeline drag only when the gesture ends. Profiling the latter
  sample found 2.18 million skipped macroblocks, 76% of them spatial-direct B blocks. Publishing
  both reference lists in one grid pass, writing motion masks one row at a time, and emitting a
  uniform spatial-direct macroblock directly as one 16x16 job reduced skip derivation from about
  54% to 44% of the CABAC parse time on the same instrumented decoder. Uniform macroblocks also
  export their co-located motion from that single job instead of resolving the same reference 16
  times.
- Per-stage now (59 frames of 1080p30, release, native): motion compensation ~870 ms, CABAC
  parse ~730 of which residual blocks ~380, deblocking ~610, YUV-to-RGB ~470, bookkeeping ~230,
  motion derivations ~210, `prepareMb` ~110.
- The `#simd` pass (2026-08-19) packed the sixteen-wide six-tap and averaging rows, then the
  eight- and four-wide six-tap filters, the whole center half-sample position (16-bit horizontal
  sums, widened vertical pass), the eight- and four-wide chroma blends, and the conversion —
  sixteen pixels per iteration with the exact 32-bit arithmetic and three `@vecperm` spreads
  for the packed stores. On the 300-frame sample, 59 frames went from about 2.5-2.7 s to about
  2.2-2.4 s (best 2498 to 2207 ms, roughly 11%), byte-exact in fast-debug and release. Recasting
  the conversion as sixteen `pmaddwd` pair sums removed the twenty `s32x4` multiplies but required
  sixteen lane interleaves; over 3,000 small High-profile frames it remained byte-exact and
  regressed release decoding from 1,117,447 to 1,340,193 us (1.20x slower), so it was discarded.
  That measurement, and the 2026-08-20 and 2026-08-21 packed results below, were taken while most
  of `Core.Math.Simd` lowered to a call into `core.dll`. The `pmaddwd` recast is the clearest case
  in the repository: it removed twenty free operators and added about thirty-two calls, sixteen
  lane interleaves and sixteen pair sums, so its verdict says nothing about the layout. Re-measure
  it first. The window, and what it does and does not cover, is in the introduction of
  `todo.simd.md`.
- The 2026-08-20 follow-up packed explicit weighted prediction for every H.264 block width
  (2/4/8/16), the common 16x16 and filtered 8x8 intra stores, and weak horizontal deblocking.
  Release microkernels improved by 2.46x/1.41x for uni/bi weighting, 2.12x to 3.20x for the 16x16
  intra modes, 1.43x for the 8x8 vertical store, and 2.66x/2.05x for luma/chroma deblocking. The
  small 96x64 fixture stayed globally neutral, so a 1080p profile remains necessary to quantify
  whole-decoder impact; every fixture and differential matrix remained byte-exact.
- The 2026-08-21 pass now routes 4x4 luma blocks whose sole nonzero coefficient is DC through the
  existing flat-add kernel, instead of dequantizing and running the complete inverse transform.
  Seven pinned samples of a complete 60-frame 1080p High/CABAC decode improve from a 2,015,365 us
  median to 1,934,459 us (1.04x), with identical frame checksums. Packing the flat-add kernel's
  four-pixel rows was globally neutral within 0.5% and was rejected. Mirroring FFmpeg's residual
  decoder, only the two significance-map CABAC decisions now inline; four stable alternating
  pinned pairs improve from a 1,750,839 us median to 1,696,958 us (1.03x), byte-exact. Inlining
  every CABAC decision remains rejected because the extra pressure regresses the parser. The
  coefficient sign now uses a dedicated branchless bypass operation, like FFmpeg's
  `get_cabac_bypass_sign`; seven pinned 1080p samples improve from a 1,901,861 us median to
  1,830,319 us (1.04x), with identical frame checksums.
- A later 2026-08-21 pass profiled a 3840x2160 Filmora High/CABAC screen recording whose P frames
  contain 75% to 94% skipped macroblocks. The decoder still cleared roughly 1.3 KiB of residual
  coefficients and carried sixteen motion jobs in every parsed macroblock, including each skip.
  Residuals now live in a cold parallel array, the common first motion job stays inline while the
  other fifteen live in cold storage, and P-skip metadata publishes four 4x4 blocks per SIMD store.
  Skipped reconstruction also returns immediately after compensation. The median of the same warm
  release frames fell from 166,779 us to 66,339 us (2.51x); the IDR frame fell from 559,007 us to
  181,884 us (3.07x). Byte-exact Baseline/Main/High, P/B, seek, and reorder fixtures pass in both
  fast-debug and release. The 4K stream is now about 15 fps rather than 5-7 fps, so it is materially
  faster but not yet real time at its 25 fps rate. sFileScope had also never initialized
  `Core.Jobs`, so all of this decoder parallelism silently ran on the GUI thread in the shipped
  application. The application now initializes the scheduler and owns frame decoding in one
  background job, coalescing seeks received while that job runs. During active playback of this
  exact 4K file, 50 consecutive window probes had a 0.25 ms median, 9.9 ms p95, 18.8 ms maximum,
  and no timeout. Scheduling each completed CABAC row for
  reconstruction remained byte-exact but regressed the warm median from 66,339 us to 68,921 us;
  it was discarded because the two stages contend for memory bandwidth without FFmpeg-style
  fine-grained reference progress.
- A 2026-08-21 pass measured the 3840x2160 25 fps Filmora recording against FFmpeg on the same
  laptop, both pinned to the performance cores: FFmpeg decodes it in about 27 ms of processor time
  per frame single-threaded and about 3 ms of wall time with frame threading. With explicitly
  inline module functions published with their bodies, the packed conversion wrappers no longer
  cross `core.dll`; the conversion stage halved and the serial decode fell to about 91 ms. The
  decoder still takes about 55-70 ms of wall time over twenty-two workers. The deblocking
  wavefront now yields after a bounded wait instead of turning a starved lane into a 230 ms stall.
  What did not pay: publishing the co-located motion in a parallel pass instead of on the entropy
  thread moved about a megabyte of scattered writes off the critical path and measured neutral to
  slightly worse, so it was dropped.
- Measured in the shipped player rather than in a bench, the same stream behaved far worse than
  any of the numbers above: sFileScope asked the decoder for the frame the wall clock was on, and
  since an inter-coded picture is decoded from the one before it, a distant target piled every
  picture in between onto a single step. Two seconds into playback the step had grown from one
  picture to thirty-two and a picture reached the screen every 0.6 to 2.5 seconds. The player now
  walks one picture at a time and only jumps when the clock is more than two seconds ahead, which
  is far enough for the decoder to restart at a sync sample: over the same seventy seconds of
  playback, alternated twice against the old behavior, 753-764 pictures reach the screen instead
  of 409-546, with 18 jumps instead of 125-146 and 15 steps over 300 ms instead of about 50,
  reaching the same point in the timeline. A bench that decodes frames in order cannot see any of
  this; measure the application.
- In that application a frame costs 100-130 ms against about 50 ms for the same frames decoded
  from the main thread with an idle pool. The decode runs inside a `Core.Jobs` job and fans its
  bands out from there, so a worker sits in `Jobs.wait` while twelve more run: 23 runnable threads
  on 22 processors, with the GUI thread among them. Frame threading has to answer this too — the
  fan-out belongs to whichever thread owns the picture, not nested inside another job.
- The critical path is now the entropy parse, about 38 ms of the 55, and it is serial by
  construction: this stream carries one slice per picture. Fine-grained frame threading is what
  FFmpeg answers with, and it is the only lever left that changes the order of magnitude. It needs
  two sets of per-picture state — the parsed macroblocks, their residuals, and the per-4x4-block
  grids, about 85 MB at this resolution — so that picture N reconstructs, deblocks and converts
  while picture N+1 parses. The parse itself does not read reference pixels, so the pipeline is
  legal; what it needs is the reference marking applied at the end of each parse rather than at
  the end of each picture.
- A second 2026-08-21 pass measured the player itself under its real clock. The commit-time
  resync policy jumped the clock target two seconds ahead, but in this all-P stream a distant
  target skips no work — the decoder walks every picture in between inside one decode job, and
  those steps reached 1.9 seconds. The player now jumps only to the next sync frame
  (`Video.Reader.syncFrameAt`, new on `IDecoder` with trivial intra-format implementations),
  which costs a single decoded IDR — this stream carries one per second — and it re-anchors the
  clock there; a stream whose next sync is more than fifteen seconds away keeps walking below
  speed instead of teleporting. The player also double-buffers its two decoded pictures and
  chains the next due decode before publishing the current one, so the texture upload overlaps
  the next decode. Measured in the running application: the worst decode step fell from 1.9 s
  to 0.24 s, and a 70-second alternated comparison showed 753-764 pictures on screen against
  409-546, reaching the same timeline position.
- The cross-picture pipeline T-504 calls for was then built and measured: reconstruction joins
  at parse end, deblocking and edge padding run as one background completion job per picture
  against buffer-swapped bookkeeping (the six arrays the filter reads), the next picture's
  in-parse reconstruction bands gate on the previous completion, and the MP4 layer parses the
  next access unit ahead of converting the current picture. Byte-exact on all 48 tests in
  fast-debug and release. Rejected: normalized against an in-process calibration loop on a
  thermally saturated machine, it bought about 4% — within noise — because deblocking was
  already parallel and short, and the two pictures contend for memory bandwidth; one 60-second
  application run also nearly stalled (62 pictures decoded) in a way that never reproduced.
  The overlap worth having must hide the CABAC parse itself, not the filter tail: that is the
  full two-picture state split, with entropy decode of picture N+1 running against the whole
  reconstruction of N, and it should be measured on an idle machine.
- During this pass the suite also failed three B-stream fixtures deterministically on an
  unmodified tree until `core.dll` was forcibly rebuilt — recorded as F-177; measurements made
  across that boundary compared two different binaries.
- Complete when: a 1080p25 High-profile stream decodes in real time in a release build. Remaining
  levers, in expected order of value: fine-grained frame/slice threading, a true byte-run
  significance decoder beyond the targeted inlining, strong and vertical packed deblocking (the
  transpose is the hard half), and a profitable packed inverse-transform strategy.
  Branchful CABAC decisions, quotient-based bypass runs, and four-byte row copies in `bookkeepMb`
  all regressed release decoding and were discarded. A 16-bit SWAR six-tap prototype stayed byte-exact but
  regressed this backend by about 13%, because expanding byte inputs cost more than the packed
  arithmetic saved — the `#simd` lanes do not pay that expansion. A trap for the parse/recon
  split: the Intra_16x16 and chroma reconstruction read residual blocks the entropy decoders
  never parsed, so the per-macroblock residual arrays must stay cleared (see `prepareMb`).

### T-424 — A video stream carries no sound

- Intent: both codecs are silent by construction, and a container that already holds an audio track
  has it skipped. A player built on this module therefore cannot play what it opens.
- Complete when: a decoder reports the audio streams of a container, hands their samples to
  `std/audio` rather than decoding sound itself, and a reader exposes the timestamp a caller needs
  to keep the two in step. AVI is the first container to carry one, since it already declares its
  streams.
- Related: T-420

### T-425 — An AVI larger than four gigabytes is refused

- Intent: every size in the AVI container is a 32-bit field, so the encoder refuses a stream that
  would run past four gigabytes and the decoder reads only the `idx1` table. OpenDML answers both
  with 64-bit `indx` chunks and a `RIFF AVIX` continuation, which is what any capture longer than a
  few minutes at a usable bitrate produces.
- Complete when: the decoder reads the `indx` hierarchy and follows `AVIX` continuations, and the
  encoder emits them instead of failing once the stream approaches the limit.
