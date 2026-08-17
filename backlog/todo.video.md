# std/video

The module reads and writes silent video as a stream: a codec registered against `Video.IDecoder`
and `Video.IEncoder`, selected by extension, reading a `Video.Source` and writing a `Video.Sink`.
Two codecs ship — YUV4MPEG2 and AVI with Motion JPEG — and both code every frame on its own, so a
reader costs one frame of memory whatever the length of the file.

What the module competes with is ffmpeg's demuxers, and the distance is measured in formats rather
than in design: what is missing is decoders.

### T-423 — Motion JPEG frames that omit their Huffman tables are refused

- Intent: a camcorder writes the abbreviated JPEG the specification allows — no `DHT` segment,
  because the decoder is expected to use the standard tables of ITU-T T.81 Annex K. `Pixel`'s JPEG
  decoder needs the segment, so those AVI files fail on their first frame with a message about a
  malformed image, which is exactly the file class an AVI reader exists to open.
- Complete when: a JPEG stream with no Huffman table decodes with the standard tables, in
  `std/pixel` where every other caller benefits from it, with a test built by stripping the `DHT`
  segment from a JPEG this repository encodes.

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
