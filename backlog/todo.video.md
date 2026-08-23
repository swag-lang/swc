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
- Measured shape of the remaining gap (2026-08-23, release, 3840x2160p25 High/CABAC, one lane and
  one worker so the figures are processor time for one picture): entropy parse 37.7 ms,
  reconstruction 19.7 ms, loop filter 9.6 ms, and 15.7 ms more for the conversion to RGB, which
  FFmpeg's 27 ms does not contain at all. Reconstruction splits into motion compensation 7.5,
  luma residual 4.1, chroma residual 3.1, intra prediction 2.5. One picture decodes 904,000 bins:
  568,603 context-coded, 310,298 through the significance-map path, 25,095 bypass. At 37.7 ms the
  parse therefore spends roughly 40 ns per bin against the few nanoseconds a tuned decoder needs,
  and that ratio, not any one stage, is the distance to FFmpeg.
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
