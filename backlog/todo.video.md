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
