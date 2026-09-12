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

### std.video.009 — H.265 range-extension chroma formats are not decoded

- Recorded: 2026-09-06 18:10
- Updated: 2026-09-12 06:47 — State the actual bit-depth checks and the supported range-extension subset.
- Evidence: `decode/hevc/sets.swg` rejects `chroma_format_idc` values other than 1, unequal luma
  and chroma bit depths, and depths above 10. The syntax supplies a minimum of 8; the conformance
  corpus covers Main/Main10 at 8 and 10 bits. The reader accepts some range-extension flags, but
  rejects extended precision, explicit RDPCM, persistent Rice adaptation, CABAC bypass alignment,
  cross-component prediction and per-unit chroma offsets. PCM, multilayer, 3D and screen-content
  tools are also refused. Current conformance coverage does not establish range-profile support.
- Next: choose a bounded range-extension profile for 4:2:2/4:4:4 input and implement its sample
  geometry and reconstruction rules. Keep unsupported extension families explicitly rejected.
- Complete when: redistributable conformance fixtures for the chosen profile match reference
  planes, malformed inputs remain bounded, and the documented limits name every unsupported tool.
- Related: std.video.005

### std.video.001 — Reduce the remaining serial cost of H.264 decoding

- Recorded: 2026-08-19 13:23
- Updated: 2026-09-12 17:40 — Record what the FFmpeg gap is made of, measured against its own build without assembly.
- Evidence: on 2026-09-12, decoding the same 3840x2160 one-slice High/CABAC clip and alternating
  the two decoders inside one measurement window, this decoder and FFmpeg's own build with its
  hand-written assembly disabled read within a tenth of each other, while FFmpeg with its
  assembly read half. Forcing its dispatch down one instruction set at a time gives the ladder
  the assembly climbs: compiled code 179, with SSE2 111, with SSSE3 82, and with everything 83.
  Alternation matters: this machine's cores are shared and its clock moves, and the same binary
  read 124 and 204 million cycles in two rounds an hour apart.
- The gap is not algorithmic. The entropy layer decodes a number of bins fixed by the bitstream,
  5.29 million per picture here, so no decoder can decode fewer; the three shortcuts that do
  carry algorithmic freedom are all taken, namely the integer-sample copy and per-phase kernels
  in `mcLuma`, the skip of a zero-strength edge in `deblockMb`, and the flat-block and
  zero-block skips in `addPlane4x4Residual`. A decoder doing materially more work per
  macroblock could not match FFmpeg's compiled code within a tenth.
- What remains is scalar. `cabac.swg` holds 46 per cent of the decode and uses no vector
  arithmetic, because an arithmetic decoder cannot: each bin is decoded from the range the bin
  before it left. At 5.29 million bins that layer costs about 16 cycles per bin. Sampling inside
  `Slice.residualCabac` shows the significance loop remaking three relocated table addresses and
  spilling the range on every bin, which is register pressure, not instruction selection.
- Current source: `Slice.resolveNeighbors` caches the four neighboring macroblocks;
  `bookkeepMb` writes grid rows and reference-picture co-located motion in words/vectors;
  `Frame.colMotion` receives the macroblock index. The old next step to build those paths is done.
  CABAC significance decoding uses caller-local arithmetic state and padded input; build 438's
  cold-call allocation fix is also shipped. Implementation chronology remains in Git.
- Remaining evidence: pre-cache profiles attributed substantial cost to context derivation and
  bookkeeping, but those percentages cannot rank the current code. Six-tap luma compensation was
  another measured gap. Reprofile before choosing among the remaining syntax and pixel kernels.
- Measurement contract: verify one VCL slice per picture, use one AVC lane, warm the reference
  set, walk forward, and interleave identical input against single-threaded FFmpeg. Read the actual
  decoding thread with `QueryThreadCycleTime` and also measure the caller to establish where work
  runs. Whole-process cycles include unrelated spinning workers; old multi-slice timings belong
  to std.video.013.
- Next: collect a current per-function profile, select one remaining kernel or bookkeeping cost,
  and compare its change on the same fixture and compiler. Keep plane digests byte-exact across
  the existing Baseline/Main/High and 4:4:4 corpus.
- Constraints: `prepareMb` must clear residual blocks that intra reconstruction can read without
  entropy parsing. Per-block overrun checks cannot be removed until the terminating path has an
  equivalent post-loop check and truncated-input coverage. Shipped packed deblocking is not new
  work; the remaining strong vertical chroma vector path belongs to cpu.simd.023.
- Avoid unqualified retries: earlier register-only CABAC and global scratch experiments did not
  establish a durable whole-picture gain; generic decision inlining was neutral under splitting.
  Recasting RGB conversion as pair sums predates cross-module SIMD inlining and needs a fresh
  comparison before its old verdict is used.
- Complete when: serial decode costs at most four-thirds of FFmpeg on the same one-slice fixture
  and machine, measured in decoding-thread cycles with unchanged decoded planes. Parity with its
  compiled code is reached; the remaining factor is its assembly, so the target is now reached by
  vector kernels in the pixel layer and by relieving register pressure in the entropy layer.
- Related: std.video.013, compiler.optimization.011, cpu.simd.023

### std.video.005 — Reduce the measured serial cost of H.265 decoding

- Recorded: 2026-08-25 08:38
- Updated: 2026-09-11 22:20 — Remove shipped SIMD and lookup work from the next step; require a current serial baseline.
- Evidence: the 2026-08-26 one-lane comparison on a 3840x2076 Main10 passage recorded 92 ms
  of processor time per picture against FFmpeg's 28.6 ms. Later stage experiments changed the
  decoder and the compiler; those numbers and old frame-access counts are historical attribution,
  not the current performance ratio. Main/Main10 conformance and container fixtures remain the
  correctness boundary. Range-extension coverage belongs to std.video.009.
- Current source: `filterLumaEdge` already sends horizontal luma to packed `filterLumaQuad`;
  vertical luma and `filterChromaEdge` remain scalar. Interpolation and inverse transforms use
  paired 128-bit arithmetic, scan inversion and significance tables are implemented, and SAO
  reuses/swaps retained planes. The old instruction to vectorize all deblocking repeats shipped
  work. The backend also has split allocation and a same-Ast last-call inlining bonus now.
- Remaining leads: threshold/context derivation and frame traffic, vertical/chroma filtering,
  locality from processing both edge directions in bounded bands, and avoiding a separate
  prediction-buffer combine for uni-predicted blocks. Attribute and choose one after measuring;
  wider SIMD capability is owned by cpu.simd.002.
- Next: rebaseline a redistributable Main10 clip with one decode lane and identical FFmpeg input,
  then profile remaining stages. Count frame accesses in the current generated kernels before
  treating compiler.optimization.011's old allocator measurements as a binding cause.
- Measurement contract: warm and decode forward without seeking back inside a measured window.
  Use paired runs and prove which threads carry decoding; for small stage changes, use alternating
  implementations within one process on the same blocks. Timing stages by disabling them changes
  downstream work and cannot attribute their costs. A fixture needing an occasionally mounted
  personal film is not a reproducible acceptance input.
- Rejected implementation boundary: removing the cross-Ast inline gate once miscompiled the
  `aoc2019` smoke, despite reducing kernel instruction counts. Publication and rebinding need
  their own proof; compiler.optimization.033 owns that path. Do not restore the gate removal.
- Complete when: serial decode costs at most four-thirds of FFmpeg on the same 3840x2076 Main10
  fixture and machine, with exact conformance and reference planes and recorded measurement scope.
- Related: std.video.001, std.video.009, compiler.optimization.011, compiler.optimization.033,
  cpu.simd.002

### std.video.012 — 4:2:2 is the chroma format H.264 still refuses

- Recorded: 2026-09-09 19:33
- Updated: 2026-09-11 22:20 — Separate 4:4:4 colour-plane coding from the 4:2:2 geometry outcome.
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
- Separate colour-plane coding is a distinct 4:4:4 feature, tracked in std.video.014.
- Next: decide whether a real file is asking for it. If one is, start from `Sps` carrying a
  horizontal and a vertical chroma shift rather than one, then the chroma DC transform.
- Complete when: a 4:2:2 fixture encoded by x264 decodes byte-exact against FFmpeg, beside the
  4:2:0 and 4:4:4 ones in `video/src/tests/datas`.

### std.video.013 — H.264 multi-slice scheduling needs its own cost and progress contract

- Recorded: 2026-09-11 22:20
- Evidence: split from std.video.001. The recorded six-slice 4K run used a banded parse/reconstruct
  path with both threads spending roughly half their samples waiting. A one-slice serial result
  cannot establish that this stream shape schedules efficiently.
- Next: preserve an openly reproducible multi-slice fixture, measure parse, reconstruction and
  wait costs separately, then choose a scheduling change that preserves reference dependencies.
- Complete when: multi-slice pictures decode exactly with bounded queues and forward progress,
  measured scheduling overhead improves on the same fixture, and the one-slice path does not regress.
- Related: std.video.001, language.parallelism.001

### std.video.014 — H.264 separate colour-plane pictures are not decoded

- Recorded: 2026-09-11 22:20
- Evidence: split from std.video.012. `decode/h264/sets.swg` reads `separate_colour_plane_flag`
  only for `chroma_format_idc == 3` and explicitly rejects it. This is a 4:4:4 picture-coding
  feature, distinct from the 4:2:2 chroma geometry that entry owns.
- Next: establish a redistributable separate-plane fixture and define slice/plane identity,
  reference state and picture completion before extending the decoder.
- Complete when: the chosen separate-plane stream matches reference planes, incomplete plane
  sets fail safely, and ordinary 4:2:0/4:4:4 fixtures retain their output.
- Related: std.video.012

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
