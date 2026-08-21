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
  four-pixel rows was globally neutral within 0.5% and was rejected.
- Complete when: a 1080p25 High-profile stream decodes in real time in a release build. Remaining
  levers, in expected order of value: a byte-run significance fast path in the CABAC engine,
  strong and vertical packed deblocking (the transpose is the hard half), and a profitable packed
  inverse-transform strategy. Branchful CABAC
  decisions, quotient-based bypass runs, and four-byte row copies in `bookkeepMb` all regressed
  release decoding and were discarded. A 16-bit SWAR six-tap prototype stayed byte-exact but
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
