# Video Backlog

The module reads and writes video as a stream: a codec registered against `Video.IDecoder` and
`Video.IEncoder`, selected by extension, reading a `Core.ByteSource` and writing a `Core.ByteSink`.
It reads YUV4MPEG2, Motion JPEG in AVI or ISO-BMFF, H.264 and H.265 in ISO-BMFF or Matroska,
and MPEG-4 Part 2 in AVI or Matroska. File-backed AVI exposes integer PCM tracks; ISO-BMFF
exposes AAC-LC, and Matroska exposes AAC-LC, AC-3, E-AC-3, DTS Core, FLAC, Layer III, Vorbis,
and Opus. Encoded payloads stay in their source; readers retain container indexes, codec
reference pictures, and bounded picture and audio buffers.

The remaining work covers codec and container breadth, decoding cost, and the lifecycle of
bounded sound windows.

Motion JPEG decoding in AVI uses Pixel's JPEG decoder. Its generic minimum-coded-unit walker accepts
the sampling layouts used by ffmpeg's 4:2:0, 4:2:2, and 4:4:4 Motion JPEG output.

### std.video.008 — ISO-BMFF does not expose Layer III sound tracks

- Evidence: `decode/mp4/mp4.swg` keeps an `mp4a` track only when its decoder-configuration
  object type is `0x40` (`Mpeg4AudioObjectType`); `0x69` and `0x6B` Layer III tracks are silently
  left out rather than rejected, although std/audio already decodes Layer III packets and the
  Matroska reader exposes them.
- Next: retain the object type while reading the audio descriptor and construct the existing
  Layer III packet stream for supported variants. Add a redistributable multiplexed fixture.
- Done when: ISO-BMFF Layer III tracks enumerate, decode, seek, and retain their timestamps
  through `Video.Reader`, with reference PCM comparisons and explicit rejection of unsupported
  MPEG audio layers.
- Related: std.audio.002

### std.video.004 — An AVI larger than four gigabytes is refused

- Evidence: AVI sizes are 32-bit, so `encode/avi/avi.swg` refuses a stream past four
  gigabytes, and the decoder reads `idx1` or walks the first RIFF's `movi` list
  (`walkFrames`), ignoring OpenDML's 64-bit `indx` chunks and `RIFF AVIX` continuations, which
  any capture longer than a few minutes at a usable bitrate produces.
- Next: read the OpenDML `indx` hierarchy and follow `AVIX` continuations in the decoder,
  then emit them from the encoder.
- Done when: the decoder reads the `indx` hierarchy and follows `AVIX` continuations, and the
  encoder emits them instead of failing once the stream approaches the limit.

### std.video.001 — Reduce the remaining serial cost of H.264 decoding

- Evidence: the last one-slice comparison put this decoder within roughly 10% of single-threaded
  FFmpeg with its hand-written assembly disabled; FFmpeg with assembly was about twice as fast.
  Measurements on the shared machine varied widely, and the decoder has since changed, so earlier
  profiles and instruction counts cannot rank current work.
- Next: collect a current per-function profile, choose one remaining serial kernel, and compare the
  change against the same FFmpeg build and fixture. Keep decoded planes byte-exact across the
  existing Baseline, Main, High, and 4:4:4 corpus.
- Measurement: use one VCL slice per picture, one AVC lane, warm references, decode forward, and
  interleave identical input against single-threaded FFmpeg. Measure the decoding thread and caller;
  whole-process cycles include unrelated workers. Multi-slice scheduling belongs to std.video.013.
- Constraints: preserve truncated-input checks and clear residual blocks that intra
  reconstruction can read without entropy parsing. The strong vertical chroma vector path
  belongs to cpu.simd.023.
- Done when: serial decode costs at most four-thirds of the selected single-threaded FFmpeg
  reference on the same fixture and machine, with unchanged decoded planes.
- Related: std.video.013, compiler.optimization.011, cpu.simd.023.

### std.video.005 — Reduce the measured serial cost of H.265 decoding

- Evidence: the last one-lane comparison on a 3840x2076 Main10 passage cost about three times
  FFmpeg's processor time per picture; the decoder and compiler have changed since, so it is
  not a current ratio. `filterLumaEdge` sends only horizontal luma to packed
  `filterLumaQuad`; vertical luma and `filterChromaEdge` remain scalar. Main/Main10 conformance
  and container fixtures remain the correctness boundary; range-extension coverage belongs to
  std.video.009, and wider SIMD capability to cpu.simd.002.
- Next: rebaseline a redistributable Main10 clip with one decode lane against identical FFmpeg
  input, profile the remaining stages, and pick one lead: threshold/context derivation and
  frame traffic, vertical/chroma filtering, band-local edge processing, or the separate
  prediction-buffer combine for uni-predicted blocks.
- Measurement: warm and decode forward without seeking back inside a measured window; prove
  which threads carry decoding; compare small stage changes by alternating implementations in
  one process on the same blocks, not by disabling stages.
- Done when: serial decode costs at most four-thirds of FFmpeg on the same Main10 fixture and
  machine, with exact conformance and reference planes.
- Related: std.video.001, std.video.009, compiler.optimization.011, cpu.simd.002

### std.video.009 — H.265 range-extension chroma formats are not decoded

- Evidence: `decode/hevc/sets.swg` rejects `chroma_format_idc` values other than 1, unequal luma
  and chroma bit depths, and depths above 10. The syntax supplies a minimum of 8; the conformance
  corpus covers Main/Main10 at 8 and 10 bits. The reader accepts some range-extension flags, but
  rejects extended precision, explicit RDPCM, persistent Rice adaptation, CABAC bypass alignment,
  cross-component prediction and per-unit chroma offsets. PCM, multilayer, 3D and screen-content
  tools are also refused. Current conformance coverage does not establish range-profile support.
- Next: choose a bounded range-extension profile for 4:2:2/4:4:4 input and implement its sample
  geometry and reconstruction rules. Keep unsupported extension families explicitly rejected.
- Done when: redistributable conformance fixtures for the chosen profile match reference
  planes, malformed inputs remain bounded, and the documented limits name every unsupported tool.
- Related: std.video.005

### std.video.012 — 4:2:2 is the chroma format H.264 still refuses

- Evidence: `decode/h264/sets.swg` fails a sequence set whose `chroma_format_idc` is neither 1
  nor 3, and `Sps.chromaShift` states one halving or none, so it cannot express half width at
  full height. 4:2:2 needs its own geometry: eight chroma blocks per plane, a 2x4 chroma DC
  transform with its own scan, a chroma quantizer offset of `+3`, and its own CABAC categories.
- Next: decide whether a real file needs it; if so, give `Sps` separate horizontal and
  vertical chroma shifts, then implement the chroma DC transform.
- Done when: a 4:2:2 fixture encoded by x264 decodes byte-exact against FFmpeg, beside the
  4:2:0 and 4:4:4 ones in `video/src/tests/datas`.
- Related: std.video.014

### std.video.013 — H.264 multi-slice scheduling needs its own cost and progress contract

- Evidence: split from std.video.001. The recorded six-slice 4K run used a banded parse/reconstruct
  path with both threads spending roughly half their samples waiting. A one-slice serial result
  cannot establish that this stream shape schedules efficiently.
- Next: preserve an openly reproducible multi-slice fixture, measure parse, reconstruction and
  wait costs separately, then choose a scheduling change that preserves reference dependencies.
- Done when: multi-slice pictures decode exactly with bounded queues and forward progress,
  measured scheduling overhead improves on the same fixture, and the one-slice path does not regress.
- Related: std.video.001, language.parallelism.001

### std.video.014 — H.264 separate colour-plane pictures are not decoded

- Evidence: split from std.video.012. `decode/h264/sets.swg` reads `separate_colour_plane_flag`
  only for `chroma_format_idc == 3` and explicitly rejects it. This is a 4:4:4 picture-coding
  feature, distinct from the 4:2:2 chroma geometry that entry owns.
- Next: establish a redistributable separate-plane fixture and define slice/plane identity,
  reference state and picture completion before extending the decoder.
- Done when: the chosen separate-plane stream matches reference planes, incomplete plane
  sets fail safely, and ordinary 4:2:0/4:4:4 fixtures retain their output.
- Related: std.video.012

### std.video.010 — Decode VP9 pictures in Matroska and WebM

- Evidence: the Matroska demuxer already accepts the `webm` document type and retains packet
  timestamps, seek points and lacing, but has no VP9 picture decoder. Its advertised extension
  is `.mkv`. Swag Scope builds its playback selectors from `Reader.decodableFormats()`, so the
  missing implementation belongs to the video module.
- Next: integrate a bounded VP9 decoder through the existing picture/plane and seek contract,
  advertise WebM when supported, and retain the existing Opus/Vorbis audio integration.
- Done when: redistributable VP9 fixtures decode and seek with reference plane comparisons,
  malformed input respects decoder limits, audio remains synchronized, and Scope discovers the
  supported format automatically while keeping its separate binary structure viewer.
- Related: std.video.011, app.scope.binary.011

### std.video.011 — Decode AV1 pictures in Matroska and WebM

- Evidence: the Matroska demuxer already accepts the `webm` document type and retains packet
  timestamps, seek points and lacing, but has no AV1 picture decoder. Its advertised extension
  is `.mkv`. Swag Scope builds its playback selectors from `Reader.decodableFormats()`, so the
  missing implementation belongs to the video module.
- Next: integrate a bounded AV1 decoder through the existing picture/plane and seek contract,
  advertise WebM when supported, and retain the existing Opus/Vorbis audio integration.
- Done when: redistributable AV1 fixtures decode and seek with reference plane comparisons,
  malformed input respects decoder limits, audio remains synchronized, and Scope discovers the
  supported format automatically while keeping its separate binary structure viewer.
- Related: std.video.010, app.scope.binary.011

### std.video.015 — Decode RealVideo 4 pictures in Matroska

- Evidence: a Matroska film with `V_REAL/RV40` is rejected because no RealVideo 4 decoder is
  registered. Matroska support for other picture codecs does not decode this stream.
- Next: implement a bounded RealVideo 4 picture decoder and connect its Matroska codec private
  data, packet framing, timestamps, and seeking to the video reader.
- Done when: redistributable RV40 fixtures decode and seek against reference pictures and malformed
  input is rejected safely, with supported sound tracks still synchronized.
- Related: app.scope.video.015

### std.video.006 — Interlaced H.264 is not decoded

- Evidence: `decode/h264/sets.swg` refuses a sequence set without `frame_mbs_only_flag`
  ("video decoder does not support interlaced H.264 streams"). A survey of one personal
  library found one such film (telecined to fields) and no interlaced H.265 or MPEG-4 Part 2.
- Next: implement field coding — `field_pic_flag`, pictures built from two fields with their
  own reference lists and picture order counts, and field deblocking and prediction rules —
  starting from a redistributable interlaced fixture.
- Done when: an interlaced fixture decodes byte-exact against FFmpeg and progressive fixtures
  keep their output.

### std.video.002 — Refreshing a bounded sound window interrupts playback

- Evidence: every Matroska sound-window rebuild publishes a new `SoundFile`
  (`publishSeekSound`), so the player replaces its voice and the listener hears the seam.
  `Audio.SoundFile.openPacketStream` copies its packet table and a voice reads it without a
  lock.
- Next: define an ownership and synchronization contract that lets a playing packet stream
  observe appended packets, then grow or hand off the window without replacing the voice.
- Done when: a long network-share playback crosses several refresh boundaries without an
  audio interruption.
- Related: std.video.003

### std.video.003 — Retired sound windows remain alive until the video closes

- Evidence: `FileIndex.seekSounds` keeps every published `PublishedSound` until `opDrop`.
- Next: make the last consumer of a window observable (player voice and decoder) and release a
  superseded window when it is gone.
- Done when: several refreshes keep only the active and genuinely referenced windows, and a
  seek cannot read freed packet storage.
- Related: std.video.002
