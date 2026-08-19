# std/video

The module reads and writes silent video as a stream: a codec registered against `Video.IDecoder`
and `Video.IEncoder`, selected by extension, reading a `Video.Source` and writing a `Video.Sink`.
Three codecs ship — YUV4MPEG2, AVI, and ISO-BMFF with Motion JPEG — and all code every frame on
its own, so a reader costs one frame of memory whatever the length of the file.

What the module competes with is ffmpeg's demuxers, and the distance is measured in formats rather
than in design: what is missing is decoders.

The picture codec of an AVI stream is the Pixel one, so what Motion JPEG this module reads is
decided there — [T-426](todo.pixel.md#t-426--jpeg-chroma-sampling-is-limited-to-one-block-per-unit)
is the layout it does not read yet.

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
