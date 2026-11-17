# Video Backlog

The module reads and writes video as a stream: a codec registered against `Video.IDecoder` and
`Video.IEncoder`, selected by extension, reading a `Core.ByteSource` and writing a `Core.ByteSink`.
It reads YUV4MPEG2, Motion JPEG in AVI or ISO-BMFF, H.264 and H.265 in ISO-BMFF or Matroska,
and MPEG-4 Part 2 in AVI or Matroska. File-backed AVI exposes integer PCM tracks; ISO-BMFF
exposes AAC-LC and Layer III, and Matroska exposes AAC-LC, AC-3, E-AC-3, DTS Core, FLAC,
Layer III, Vorbis, and Opus. Encoded payloads stay in their source; readers retain container indexes, codec
reference pictures, and bounded picture and audio buffers.

The remaining work covers codec and container breadth, decoding cost, and the lifecycle of
bounded sound windows.

Motion JPEG decoding in AVI uses Pixel's JPEG decoder. Its generic minimum-coded-unit walker accepts
the sampling layouts used by ffmpeg's 4:2:0, 4:2:2, and 4:4:4 Motion JPEG output.

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
- Progress: CAVLC coefficient-token decoding uses a generated first-byte lookup for short codes
  and keeps the ordered search for ambiguous prefixes. The lookup covers 248 to 252 of the 256
  prefixes per table; exhaustive 16-bit prefix comparison and truncated-input tests preserve the
  previous result and bit-reader state. Its effect on complete decoding still needs measurement.
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
  not a current ratio. `filterLumaEdge` uses packed four-line luma filtering in both
  orientations, transposing vertical segments, while chroma packs two-line segments in both
  orientations. Main/Main10 conformance and container fixtures remain the correctness boundary; range-extension coverage belongs to
  std.video.009, and wider SIMD capability to cpu.simd.002.
- Next: rebaseline a redistributable Main10 clip with one decode lane against identical FFmpeg
  input, profile the remaining stages, and pick one lead: threshold/context derivation and
  frame traffic, the vertical luma transpose, band-local edge processing, or the separate
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

### std.video.015 — H.264 encoding needs rate control and 4K60 throughput

- Evidence: `encode/` writes Motion JPEG in MP4 and AVI, plus Y4M. A borrowed encoded-packet
  contract and a fragmented MP4 writer now consume H.264 access units. `H264.AnnexBAccessUnit`
  converts Annex B encoder output and extracts `avcC`. `Video.Nv12Frame` converts packed RGB and
  BGRA pictures to top-down BT.709 NV12. The portable Constrained Baseline encoder emits
  exact I_PCM macroblocks, flat intra blocks, exact integer-pixel inter copies and P-skip;
  its packets round-trip through the module and FFmpeg. In Release on the Linux test machine,
  a textured 1080p IDR took 22.8 ms and 3.15 MB, a 16-pixel vertical scroll 5.0 ms and
  97.6 KB, a static P picture 3.6 ms and 11 bytes, and a flat IDR 3.3 ms and 8.6 KB.
  A two-second software BGRA-to-NV12, H.264, full-band stereo AAC and fragmented-MP4 test
  with 120 static 1080p frames finished in 1.59 seconds; alternating two textured pictures
  shifted by 16 pixels finished in 1.66 seconds. Arbitrary textured changes still
  fall back to multi-megabyte I_PCM pictures; that path is not ready for production capture.
  `Video.FramePacer` maps monotonic arrivals to exact frame slots and reports skipped slots over
  long recordings without accumulating time rounding.
  Parallel software BGRA8-to-NV12 conversion with SIMD luma takes 1.285 ms per warmed
  1920×1080 frame and 3.819 ms per warmed 4K frame in Release, down from 2.184 and
  8.584 ms for the preceding parallel scalar path on the same fixtures. A 4K varying-color
  parity test matches every output byte against the scalar BGR8 path; a six-pixel width also
  exercises the SIMD group and scalar remainder in one row.
  A one-second synthetic 4K60 scrolling sequence with stereo AAC takes 2.07 seconds through
  software conversion, H.264 and fragmented MP4 on this machine. Real screen acquisition and
  further H.264 compression still need measurement. Exact 4×4 luma and chroma DC/AC residuals
  now compress changed macroblocks instead of falling back to raw I_PCM where possible, with
  byte-exact round trips through `Video.Reader` and FFmpeg. A sparse chroma-change profile
  encodes a 1080p picture in 12.7 ms at 65,382 bytes and a 4K picture in 51.0 ms at 263,353
  bytes on this machine. The 4K profile is still about three times slower than a 60 fps frame
  budget. A dense-changing 4K P picture now uses a cheap luma-delta classifier before
  attempting expensive exact AC coding: Release encode time fell from about 295 ms to
  71–75 ms, with a 0.46% larger packet. The other measured stress pictures kept their
  packet sizes, and FFmpeg decoded both 4K pictures byte-exactly. This is still over four
  times a 60 fps frame budget. The real X11 4K60 dynamic scene with stereo AAC took
  2.47 seconds for capture, conversion, exact H.264 and MP4, producing a 99.17 MB file;
  the earlier measurements of this scene were 2.23–2.75 seconds, so this optimization
  does not establish a whole-pipeline gain for that scene. The live encoder now accepts
  fixed QP 0–51: QP 0 preserves the exact path, while positive QP uses quantized luma/chroma
  intra and inter residuals with reconstructed references. A candidate larger than PCM still
  uses exact PCM. `Mp4.SoftwareRecording` forwards the optional QP and 1–8 parallel row-band
  slices through all three constructors, defaulting to QP 0 and one slice. Six-picture
  QP 0/28/36 recordings reopen through `Video.Reader` and FFmpeg; repeated pictures decode
  identically to their predecessors. The 64×64 MP4 probe measured 32,121 / 10,391 / 7,552
  bytes respectively.
  On the Linux test machine, a textured 1080p P picture at QP 28 has a 522,924-byte median
  packet and takes 50–63 ms; at QP 36 it has a 135,445-byte median packet and takes 39–48 ms.
  The corresponding 4K P pictures take 200–229 ms at 1,920,587 bytes (QP 28), and
  147–186 ms at 359,130 bytes (QP 36). Three-picture stress sequences round-trip through
  `Video.Reader`; QP 28 luma PSNR stays above 36.17 dB and QP 36 above 31.49 dB on these
  fixtures. Repeating unchanged raw input after a lossy P previously recoded residuals against
  the reconstructed reference; the input cache now emits 11-byte P-skip packets for P2–P4,
  lowering the 4K QP 28 median from 635,442 bytes/166.3 ms to 11 bytes/12.94 ms without
  changing Reader output. FFmpeg also decodes the quantized four-picture H.264 probe.
  On the X11 4K60 dynamic scene with stereo AAC, fixed QP 28 initially took 10.27–11.05
  seconds for capture, conversion, H.264 and MP4 and produced 53.60 MB. Uniform-DC and
  CAVLC shortcuts plus four parallel slices brought this to about 4.17 seconds and 51.35 MB,
  with 44.64 dB luma PSNR on the final picture. Residuals against a shifted reconstructed
  reference further reduce the same scene to 3.88 seconds and 21.89 MB at QP 28, with
  45.40 dB final-frame luma PSNR; QP 36 takes 3.71 seconds and 10.06 MB, at 38.10 dB.
  FFmpeg decodes all 60 QP 28 pictures without errors and measures 44.61 dB mean luma PSNR
  against an exact recording. The same four-slice scene at exact QP 0 takes 1.37–1.51
  seconds and 7.78 MB with the one matching (−16,−8) vector. On this machine, two slices
  take 4.75 seconds at QP 28, while eight take 3.85 seconds; four and eight are close.
  A direct inter-CBP lookup replaces a 48-entry scan: the lookup alone falls from 166.6 to
  6.7 ms over 10.8 million operations weighted by the scene's actual patterns, with identical
  bitstreams. A proven zero-coefficient bound halves the luma quantizer's cost on sampled
  moving-tile blocks (9.35 to 4.85 ms over 102,400 calls), without changing coefficients or
  reconstructed pixels across QP 0–51. Whole-capture timings remain noisy and have not
  established an additional end-to-end gain from these two shortcuts.
  In this scene QP 28 video totals 21.86 MB versus 7.75 MB at exact QP 0; a color wrap in the
  flat background makes one QP 28 P picture 1.73 MB. Fixed QP is not yet a useful bitrate
  guarantee, even on a regular screen animation.
  For QP 28, a bounded quantized Intra16x16 candidate in P slices now restores flat regions
  whose lossy reconstructed borders prevent the empty intra form. A flat-source luma shortcut
  and a chroma DC shortcut keep the quantizer's output byte-identical. The chroma shortcut
  halves its isolated 200,000-call cost. The same X11 4K60 scene with four
  slices took 2.40–2.93 seconds across earlier measured runs for capture, conversion, H.264 and MP4.
  A portable row-comparison shortcut for complete flat macroblocks then reduced a paired
  run from 2.514 to 2.340 seconds with a byte-identical MP4; the Video suite passed
  310/310 tests and FFmpeg decoded 60/60 pictures. Direct quantization of the one
  nonzero Intra16 luma DC coefficient then cut its flat-block microbenchmark by 35%
  at QP 28 and 36 and moved one app run from 2.340 to 2.289 seconds with the same
  size and PSNR. A single-DC CAVLC path for proved flat P Intra blocks then moved
  a paired run from 2.301 to 2.229 seconds with the same AAC version and a
  byte-identical MP4. The final file is 4.159 MB after separate AAC section savings
  and reaches 48.41 dB final-frame luma PSNR.
  The largest previous P packet falls from 1.73 MB to 81 KB. The flat P Intra path
  also supports QP 36 after an isolated Reader regression: the earlier path took
  3.55–3.73 seconds, 10.06 MB and 38.10 dB on this scene; the new 4K60 app
  run took 2.214 seconds, 3,180,677 bytes and 40.26 dB. FFmpeg decoded all 60 H.264
  pictures and the AAC track. Reader decoded the last QP 36 picture in isolated runs
  at one, two and three workers (1/1, 6/6 and 6/6). A previous app verification stall
  was not reproduced in isolation; the separate intermittent app/Reader stall remains.
  On two QP 28 P frames with about 28,000 accepted flat Intra blocks each, temporary
  per-slice instrumentation attributed 10.6–13.5 ms CPU to luma quantization,
  7.3–9.3 ms to chroma, 6.0 ms to result copies, 5.1–5.2 ms to classification
  and 3.8–3.9 ms to CAVLC, summed across four slices rather than wall time.
  Skipping unused luma AC copies did not improve complete app timings consistently
  in paired QP 28/36 runs, so that experiment was removed.
  These profiles remain above the 16.7 ms per-picture budget. One exact 4K IDR can still
  occupy about 12.5 MB; at 60-frame GOP spacing this alone implies roughly 100 Mb/s at 4K60.
  Quantized intra reduces a 4K textured IDR to 336 KB at QP 36 in one fixture (39.44 dB
  luma PSNR), but another fixture yields 2.21 MB (30.58 dB); both decode in FFmpeg. The
  IDR also takes longer to encode than its PCM counterpart on both fixtures.
  `H264.RateControl` now computes a fractional picture budget and bounded QP steps from
  observed packet sizes, but it is internal and not connected to the recorder.
  `H264.Encoder.repeatPrevious` now writes a P-skip picture for an explicitly held frame,
  while still writing an IDR at the configured interval. In a Release 3840×2160 probe,
  a held picture took about 5 µs and 11–53 bytes with one or four slices, versus
  31–57 ms for the changing P picture; Reader decoded the held picture identically
  in exact and quantized tests. This saves work for missed capture slots, not for
  fresh pictures that happen to be visually unchanged. The encoder now compares fresh
  input with its preceding source picture before macroblock analysis. In a Release
  3840×2160 probe, a fresh but identical picture took 1.2–1.6 ms and emitted the same
  11–53-byte P-skip packet, while the changing P picture took 39–73 ms.
  `regionMotion` now compares each luma region with the preceding source picture before
  building row/column motion profiles. On a deterministic 1080p30 QP 28 clip with a moving
  384-pixel tile over an unchanged textured background, five paired Release runs had a median
  8.3% encode-time reduction (group medians were 303 and 282 ms); a 12-picture 3840×2160
  localized-motion run fell from 718,592 to 528,148 µs (26.5%). Packet bytes, MP4 bytes,
  decoded hashes, PSNR and SSIM all matched. Six paired all-changing 1080p30 controls had a
  2.0% median slowdown;
  one pair was 23.6% slower, while the other five ranged from essentially equal to 13.1%
  slower. These codec-only synthetic results have substantial run variation and do not claim
  a physical-display capture throughput gain.
  The X11 4K60 integration stress test now also has a fixed-background mode that moves four
  512×512 tiles. On a 3840×2160 Xorg virtual root at QP 28, 60-frame capture/encode/MP4 time
  fell from 3.42 to 2.64 seconds with four slices (22.8%), and from 3.15 to 2.64 seconds
  with eight (16.2%). Within each slice count, baseline and optimized MP4 files were
  byte-identical (401,320 and 1,001,609 bytes respectively), with identical decoded hashes
  and luma PSNR (49.89 and 47.64 dB). The timer includes X11 root readback, conversion,
  H.264 and MP4; painting and AAC are reported separately. This validates the software
  capture path on a virtual display, not a physical Windows desktop.
  An incremental exact-YUV region check now also skips the repeated per-macroblock source/reference
  comparisons when every luma and chroma sample in a region is unchanged. In alternating
  baseline/candidate/candidate/baseline 4K X11 static-background runs at QP 28 and four slices,
  capture/encode/MP4 averaged 3.71 seconds before and 2.79 seconds after (24.8% faster); all four
  output MP4s were byte-identical (401,320 bytes, SHA-256 `e760ca2c...022fd99d`) with identical
  decoded pictures and 49.89 dB luma PSNR. A full-screen changing 4K pair was 3% slower with the
  candidate, within observed run variation. A 1080p chroma-only control averaged 9% slower because
  it scans chroma across a luma-unchanged region before falling back to per-macroblock checks.
  The gain therefore applies to regions unchanged in all three planes; it does not establish a
  general throughput gain for changing scenes. Focused Release H.264 tests passed 8/8.
  Motion search now stops accumulating a candidate SAD once its partial score reaches the
  strict winner bound; losing candidates cannot change the selected vector or output. Focused
  Release H.264 tests passed 9/9 with this change. On a
  1080p30 code-window scroll clip at QP 28/four slices, alternating baseline/candidate runs
  averaged 364 to 325 ms (10.7% faster). Packet and MP4 sizes, decoded hashes, PSNR and SSIM
  matched exactly. On a scaled-up 4K screen-content clip the candidate was effectively even
  (503 vs 502 ms); on a changing full-screen 4K control it was 2.8% slower, within run
  variation. These results are workload-dependent and the encode-only benchmark does not
  establish a capture-cadence gain for a physical display.
  BGRA-to-NV12 conversion now reuses its two packed SIMD loads to calculate adjacent 2×2
  chroma blocks together. Two idle paired Release runs reduced conversion time per frame by
  a median 15.5% at 1080p (1,247/1,071 to 1,047/912 µs) and 23.6% at 4K
  (5,836/4,613 to 4,521/3,466 µs). The existing integer coefficients, rounding and clamp
  are unchanged; 4K BGRA/BGR output parity and edge cases pass byte-for-byte checks. Focused
  NV12 Release tests passed 10/10, including the 1080p and 4K conversion stresses. These are
  conversion-only gains, not complete-recording cadence measurements.
  On the same virtual root with a changing full-screen background, two QP 28 runs per slice
  count measured median video capture/encode/MP4 time of 8.01 seconds for four slices and
  7.45 seconds for eight (6.9% faster). Eight slices emitted 3.43 MB at 46.17 dB luma PSNR,
  against 2.98 MB at 43.75 dB with four; both passed with no repeated slots. This unpaced
  synthetic run is below 60 fps and does not establish physical-display cadence.
  At QP 22, one run per slice count took 8.82 seconds with four slices and 8.14 with eight
  (7.6% faster); the four-slice output was 2.94 MB at 54.74 dB, and the eight-slice output
  3.78 MB at 52.85 dB. Rate and quality changes with slice count are content-dependent.
  On that localized 1080p clip at QP 28, Swag emitted 871 KB of packets at 39.50 dB luma
  PSNR; x264 Baseline/veryfast at fixed QP 28 emitted 732 KB at 39.95 dB, while
  x264 Baseline/ultrafast at CRF 28 emitted 954 KB at 40.42 dB. CRF is not equivalent to QP,
  and x264's measured process time includes startup and muxing while Swag's timer covers only
  encoding; these are rate-quality references, not direct speed ratios.
  On the 12-picture 4K localized-motion clip at QP 28, Swag emitted 3.32 MB at 39.96 dB
  luma PSNR; x264 Baseline/veryfast at fixed QP 28 emitted 2.69 MB at 40.16 dB, and
  Baseline/ultrafast at CRF 28 emitted 3.40 MB at 40.52 dB. Swag's encode-only timer was
  552 ms and x264's process took 317 ms, but those timings include different stages and are
  not directly comparable.
  On a scaled 1080p30 desktop-code scroll at QP 28, Swag emitted 224 KB at 43.90 dB luma
  PSNR and 0.9949 luma SSIM. x264 Baseline/veryfast at fixed QP 28 emitted 245 KB at
  43.27 dB/0.9948; Baseline/ultrafast at CRF 28 emitted 392 KB at 43.72 dB/0.9941.
  High/veryfast CRF 28 emitted 129 KB at 39.32 dB/0.9924. QP and CRF are not equivalent,
  and x264 process time includes startup and muxing while Swag reports encode-only time.
  Screen recording in Swag Capture (app.capture.011) needs a modern
  codec at 4K and 60 frames per second, while the module already decodes H.264.
  A deterministic four-slice stress case now measures 100 alternating 4K P pictures at
  QP 18 and 28. On a Windows run with lower contention, QP 18 took 3.79 seconds and emitted
  28.49 MB; QP 28 took 4.00 seconds and emitted 15.33 MB. A preceding run under
  concurrent load took 8.03 and 30.39 seconds, so fixed QP is a size choice, not a
  reliable latency control.
  Reusing per-slice scratch storage took 4.02–4.19 seconds against 4.11 seconds with
  local arrays on one Windows checkout, with identical 15.33 MB packets. The difference
  is below run variation, so that scratch experiment was removed. Direct, persistent
  per-slice motion, PCM and residual arrays now avoid allocating those tables for every
  picture. A later Release 3840x2160 on/off/on run took 2.726/2.920/2.753 seconds for
  100 changing QP 18 P pictures and 2.799/2.972/2.786 seconds at QP 28, with the same
  packet byte counts. The 42 focused H.264 functional tests and two 4K stress tests passed;
  a 30-second full-desktop Swag Capture file decoded 901 pictures without missed slots.
  The earlier scratch attempt exchanged local arrays; this version accesses encoder-owned
  arrays directly, and the measured gain is confined to this workload.
  Film content was the worst case of that quantized path: a 245-second Swag Capture recording of
  a film playing in a 2664×1078 area at QP 18 came to 1.47 GB, about 48 Mbit/s, and fourteen
  steps of quantization only halved the stream: the cost was in prediction, not in residual
  precision. Positive QP now runs a separate coder (`encode/h264/lossy.swg`) that replaces every
  quantized-path figure above: Intra_16x16 and Intra_4x4 prediction, one quarter-sample vector
  per macroblock found from neighbours, a per-region translation estimate, long jumps and a
  hexagon search, P-skip, dead-zone quantization with coefficient elimination, in-loop
  deblocking, and edge macroblocks coded like the rest instead of raw. It predicts from the
  decoder's own `Frame`, and FFmpeg rebuilds its reference bit for bit. On three one-second
  clips of that film (dark, bright, mixed) with eight slices in Release, QP 26 first gave 3.5,
  4.3 and 3.0 Mbit/s at 46.3, 43.7 and 46.0 dB luma PSNR, against 18.9, 48.1 and 30.0 Mbit/s at
  47.4, 44.5 and 46.4 dB before. x264 at baseline, veryfast and QP 26 reaches 3.0, 4.1 and
  2.5 Mbit/s at 47.6, 43.9 and 46.4 dB: at equal PSNR that first coder needed 35% more bits.
  x264's own statistics showed why: in predicted pictures it codes 11–13% of the macroblocks
  as Intra_16x16, smooth areas whose light changed, and nearly no inter residual. The intra
  and inter choices are now made on Hadamard-transformed differences, a predicted picture
  tries Intra_16x16 against every inter macroblock that is not at rest, and key pictures are
  coded three steps finer. QP 26 now gives 3.3, 4.6 and 3.0 Mbit/s at 47.8, 44.2 and 46.7 dB,
  8% above x264 at equal PSNR with eight slices and 4% with four; one slice is level with it.
  Measured and rejected: skipping every macroblock whose residual at the skip vector quantizes
  to nothing (7% fewer bits, half a decibel lost, a net loss), a bonus for the skip vector,
  and pruning the slanted Intra_4x4 modes. A region estimate sampled every fourth row and
  column misses fine periodic detail. One slice takes about 50 ms on a 2664×1078 picture:
  the region estimate, the motion search and intra coding are the three largest shares.
- Next: remeasure the complete 1080p60 and 4K60 capture paths with the new coder, which spends
  about 26 ms on a 2664×1078 film picture with eight slices. Slices cost 5% of the stream:
  code one slice in parallel waves, decisions first and bits after, to drop them. Vectorize the
  region estimate, the 4x4 transforms and the Intra_4x4 predictions. Then 8×8 and 16×8
  partitions, which x264 uses on 2–5% of these macroblocks, and a trellis or adaptive dead
  zone; CABAC needs the Main profile. Give the exact QP 0 path the same motion search.
  The app allows eight slices up to 4096 pixels and four above that, where downscaled desktop
  readback also needs CPU. In a 10-picture 4K testsrc Release benchmark, eight slices encoded
  17–30% faster than four, with under 0.5% file-size and 0.01 dB luma-PSNR differences. A scaled
  two-screen live recording instead lost 363 slots with eight slices in one run and none with
  four in a later run under varying load. Remeasure 1080p60 and 4K60 capture with concurrent
  readback; codec-only timing does not choose the end-to-end slice count.
  `Mp4.SoftwareRecording` now accepts an optional `SoftwareVideoRateControl` with a target rate,
  reservoir capacity and bounded QP range. It feeds each completed packet's byte count and exact
  frame-slot duration back into the controller, exposes the chosen QP and cumulative H.264 packet
  bytes, and prevalidates budget arithmetic before encoding. Focused tests cover QP adaptation and
  bounds, repeated capture
  slots, and a finalized fragmented MP4. This controls average rate; it cannot bound one packet or
  guarantee a file size when even QP 51 falls back to PCM, and the recorder has no scene-cut
  detection. Treat a failed MP4 packet submission as terminal or make submission transactional.
  Remaining work is measuring changing screens and scene cuts through Reader and FFmpeg, exposing
  per-frame encode latency and dropped-frame counters, and meeting the 1080p60/4K60 capture target.
  Use a platform encoder only if the software path cannot meet the required profile; do not add an
  external codec library for a capability that can be implemented in Swag.
- Done when: captured 1080p60 and 4K60 sequences produce playable H.264 files at useful
  bitrates, the module's decoder and a reference player both read them, and the recorder reports
  rate control, encode latency and dropped frames.
- Related: app.capture.011, std.video.016, platform.portability.099

### std.video.016 — Fragmented MP4 needs timed metadata and indexed playback

- Evidence: `Video.Writer` still drives one `IEncoder` that owns both codec and container, and
  its MP4 path writes Motion JPEG with the sample table at the end. A separate
  `Mp4.FragmentedWriter` now accepts length-prefixed H.264 packets with decode and presentation
  times, groups video and AAC packets per track into bounded `moof`/`mdat` pairs (one packet per
  fragment by default), and flushes completed fragments. FFmpeg reads grouped video with two AAC
  tracks and a file stopped at a fragment boundary. `Video.Reader`
  scans samples in video and AAC-LC audio fragments and recovers completed frames and sound packets
  when the final fragment or final index is cut. The writer has one video track, up to four sound
  tracks, and an optional 64-bit `mfra`/`tfra` key-frame index written with bounded memory through
  temporary disk storage. It reports submitted video and audio packet counts, track end times,
  and bytes written after completed groups, so a recorder can monitor duration and size.
  `Mp4.FragmentedWriter.resume` scans the
  complete media prefix and continues a stopped file, retaining the video and AAC clocks and
  replacing an old or incomplete final index. `Mp4.FragmentedIndex` reads a completed file's
  final index from its tail and locates key frames with binary search.
  `Mp4.FragmentedPacketCursor` walks compressed video and AAC packets one fragment at a time with
  a bounded sample window. It reads payload only on request, reports each packet's fragment
  location and the last complete media boundary, and can start at an indexed video key frame.
  `Mp4.summarizeFragmentedRecording` reports packet counts, track decode-time endpoints, the
  last complete media boundary, and an interrupted tail through the same bounded cursor.
  `Mp4.rebuildFragmentedIndex` trims an incomplete final box or prior index and writes a new final
  index from a bounded temporary spool. A sparse 64-bit offset stress test places a decodable
  indexed fragment beyond 4 GiB. `Video.Timebase` converts absolute timestamps between integer
  clocks without per-packet rounding drift; AAC cuts use it to map
  video boundaries to sample clocks. `Mp4.planVideoTimeRanges` maps requested decode-time
  intervals to key-frame packet ranges with a bounded fragment scan. Software H.264 and AAC
  packets now round-trip through this writer and `Video.Reader`, and FFmpeg plays the file. A
  test starts video one AAC priming packet after audio; `Video.Reader` trims exactly 1024 decoded
  samples and aligns the audible signal. `Mp4.SoftwareRecording` now applies that video offset,
  buffers arbitrary PCM chunks, and finalizes the H.264/AAC file; a simulated lost microphone
  block round-trips as silence in the decoded MP4. The facade can now encode up to four
  separate sound tracks with aligned audible time zero; a two-track test decodes microphone
  and system sound and verifies correlation with their distinct input tones. A one-second
  1080p60 stress test with four sound tracks encodes 60 pictures and 192 AAC packets in
  0.517 seconds in Release on the Linux test machine, and all four tracks reopen at the
  expected sample position. A 44.1 kHz integration test found that rounding the 90 kHz video
  preroll upward removed 1025 AAC samples; the facade now chooses the preceding video tick,
  verifies that the clock can still identify exactly 1024 priming samples, and rejects a
  timescale too coarse to do so. `SoftwareRecording.createVideoOnly` now writes a playable
  video track with no empty AAC track and no priming when sound is unavailable or disabled.
  On finalization, the writer now publishes standard edit lists from reserved `free` boxes;
  `Video.Reader` applies AAC priming and trailing trim and reports the exact source frame count,
  including partial final packets at 44.1 and 48 kHz. Completed fragment prefixes remain
  readable before finalization. FFmpeg applies leading AAC edits but still exposes up to 1023
  padded samples at the end of fragmented MP4. Independent PyAV decoding of the two-hour fixture's
  89-picture tail returns 142976 samples instead of 142400 after a packet-copy trim; full software
  conversion returns 143360. Native decoding returns exactly 142400 in both cases. The writer has no timed metadata
  tracks; `Video.Reader` still scans fragments to build its frame table when opening a file.
- Next: add timed metadata tracks with interleaving, and extend `Video.Reader` to those tracks.
  Make finalized AAC end boundaries portable to reference players, checking a final nonfragmented
  publication/index or packet discard metadata rather than changing the user's selected picture range.
  Retain the resumable prefix and byte-identical compressed interiors.
  Use the final key-frame index for fast seeks without scanning a long file. Keep 64-bit offsets
  and a timescale that does not accumulate rounding. Keep the current single-stream writer as a
  facade.
- Done when: a recording with video, two sound tracks and a metadata track plays in the module's
  decoder and in reference players; a file cut at any fragment boundary still plays to it; and a
  synthetic four-hour, multi-gigabyte stream seeks to any instant from its index while the muxer's
  memory stays flat.
- Related: std.video.015, std.video.017, std.audio.015, app.capture.011, app.capture.013,
  app.capture.034

### std.video.017 — Packets cannot be copied between files

- Evidence: `Mp4.FragmentedPacketReader` now exposes demuxed H.264 and AAC-LC packets with their
  source track timestamps and decoder configurations. A video and two-sound-track remux preserves
  packet bytes and times without decoding. `Mp4.copyVideoRanges` joins selected closed H.264 groups
  on key frames using two progressive fragment-header passes and bounded memory. `Mp4.copyRanges`
  also uses those passes to join AAC-LC tracks, with cumulative rounding to whole AAC
  packets; a six-join test keeps the audio within half a packet of video time at every join.
  Both replace the output only after it is complete. `trimSoftwareRecording` additionally performs
  a single frame-exact cut with sample-exact AAC presentation edits in the native reader, preserving
  transform preroll and existing edits across repeated cuts. The multi-range join APIs still use
  packet-granular AAC, and the writer has no timed metadata track.
- Next: add timed metadata to the packet path when available, and extend exact audible edits to
  multi-range joins without accumulating rounding or exposing each retained preroll passage.
- Done when: a recording cut into kept ranges on key frames produces a file whose packets are
  byte-identical to the source's, with continuous timestamps and sound in sync across each join.
- Related: std.video.016, app.capture.037
