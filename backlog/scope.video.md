# Swag Scope Video Viewer Backlog

The Video viewer already performs progressive decode, frame-accurate indexed presentation for its
supported codecs, audio-clock synchronization, track selection, sidecar and embedded subtitles,
seeking, full-screen hosting, mute, and volume. This backlog owns professional playback and
inspection around `std/video`; codec implementation work remains in [video.md](video.md).

## Professional transport

### B-117 — Video playback has no speed or pitch policy

- Evidence: playback runs at the stream rate only. There is no 0.25x–4x selector, frame-rate
  override, pitch-preserving audio mode, or indication of the frame-drop/duplication policy.
- Next: make the media clock rate-adjustable and add audio resampling with pitch-following first,
  leaving pitch preservation explicitly unavailable until implemented.
- Complete when: rate is visible and keyboard adjustable, time labels remain source-time based,
  A/V sync and subtitle timing hold at supported rates, frame scheduling declares drops, and reset
  returns exactly to 1x.

### B-118 — Video has no previous/next frame or exact time/frame address

- Evidence: Left/Right seek by ten seconds and the timeline seeks approximately. A reader cannot
  step one decoded frame while paused, enter a timestamp, seek to a presentation frame/index, or
  inspect keyframe versus decoded-frame boundaries.
- Next: add paused frame stepping and a timecode address box backed by presentation timestamps,
  then expose keyframe/preroll information where the container provides it.
- Complete when: previous/next frame reaches the exact display order, numeric time and frame jumps
  validate their interpretation, variable-frame-rate content never invents a constant mapping, and
  the current PTS/DTS/keyframe state is inspectable.

### B-119 — Video cannot mark or loop an A/B range

- Evidence: the timeline carries only a playhead. There is no set A/B, range selection, loop,
  play-once selection, or duration readout for a scene under inspection.
- Next: reuse the source-time range contract from B-107 on the video clock and seek pipeline.
- Complete when: A/B can be set by pointer, timecode, or current frame; looping accounts for decode
  preroll without showing earlier pictures; subtitles/audio repeat in sync; and clearing the range
  restores normal end behavior.
- Related: B-107

### B-120 — Chapters, editions, markers, and seek history are absent

- Evidence: container chapters and Matroska editions are not surfaced, and repeated seeks have no
  back/forward history or temporary bookmarks.
- Next: normalize container chapters/editions and sidecar chapter files into a landmark track,
  followed by session bookmarks and navigation history.
- Complete when: chapter list, previous/next, edition selection, temporary named markers, and
  back/forward preserve exact times; invalid/overlapping chapters warn; and bookmarks export without
  modifying the video.

### B-121 — Timeline seeking has no thumbnails or buffered/decode-cost feedback

- Evidence: dragging shows a time position only. There is no hover/scrub thumbnail, keyframe marks,
  buffered range, pending-seek state, decode distance, or distinction between exact and approximate
  seek.
- Next: build cancellable thumbnail tiles at keyframe-spaced landmarks with a strict memory and CPU
  budget, then annotate pending and ready ranges.
- Complete when: hover and keyboard scrubbing preview nearby frames, obsolete requests cancel,
  exact versus approximate results are labelled, sparse indexes remain usable, and playback has
  priority over thumbnail work.

## Presentation and tracks

### B-122 — Aspect ratio, crop, rotation, mirroring, and zoom cannot be corrected

- Evidence: frames fit the available view using decoded geometry. The reader cannot inspect or
  override sample/display aspect ratio, rotation metadata, clean aperture, crop, zoom, pan, mirror,
  or stretch policy.
- Next: separate coded size, clean aperture, display transform, and temporary view transform, then
  expose Fit, Fill, Actual Pixels, and declared-aspect modes.
- Complete when: source and effective geometry are visible, rotation/mirror/aspect overrides are
  reversible, pan/zoom is bounded, subtitle placement follows display geometry, and screenshots
  use the chosen explicit transform.

### B-123 — Color, HDR, range, chroma, and deinterlace decisions are invisible

- Evidence: the summary names codec and CPU decoder but not matrix, primaries, transfer, full versus
  limited range, chroma location, bit depth, HDR metadata, tone mapping, or interlace handling.
  B-564 covers missing interlaced H.264 decode, not the viewer controls and diagnostics.
- Next: surface stream color/interlace metadata and conversion path, then add safe temporary
  override and comparison controls as the video/pixel pipelines support them.
- Complete when: source and output color facts are inspectable, unspecified values state defaults,
  HDR/tone-map and deinterlace modes are explicit, overrides reset cleanly, and a test chart verifies
  range and matrix handling.
- Related: B-207, B-314, B-316, B-564

### B-124 — Subtitle files can only be auto-discovered, not deliberately loaded and managed

- Evidence: same-stem sidecars are discovered and a menu selects embedded or found tracks. There is
  no Open Subtitle File, reload after edit, encoding override, multiple simultaneous tracks,
  preferred-language policy, safe-area guide, or list of parse warnings.
- Next: add explicit local sidecar attachment and a subtitle-track manager reusing the standalone
  viewer's diagnostics.
- Complete when: arbitrary supported sidecars can be attached/reloaded/detached, encoding and FPS
  policy are visible, primary and secondary tracks can coexist, parse warnings link to cues, and
  language preference persists without hiding other tracks.
- Related: B-060, B-061

### B-125 — Audio synchronization and channel output cannot be inspected or corrected

- Evidence: subtitle delay is adjustable, but audio delay is not. Track entries show codec,
  channels, and rate while channel layout, downmix matrix, language/default/forced flags, loudness,
  and A/V drift are hidden.
- Next: expose audio-track metadata and measured clock drift, then add reversible audio delay and
  diagnostic channel/downmix selection.
- Complete when: delay adjusts in fine and coarse steps, current drift and selected layout are
  visible, track flags/language/title are preserved, downmix policy is inspectable, and reset returns
  to container timing.
- Related: B-633, B-110

### B-126 — Track and stream metadata have no complete media-information panel

- Evidence: the host summary compresses picture size, codec, FPS, frame count, and one audio detail.
  Container brands, duration provenance, bitrate, time base, frame-rate mode, codec profile/level,
  pixel format, track IDs, language/flags, tags, attachments, chapters, and decoder warnings are not
  presented together.
- Next: define a container/stream metadata tree and publish it through B-046 without coupling it to
  transport widgets.
- Complete when: container plus every stream has exact technical metadata and original tags,
  derived values identify their source, attachments open safely, warnings link to track/time where
  possible, and the report can be copied/exported.
- Related: B-046

## Capture, performance, and continuity

### B-127 — A frame cannot be copied, saved, or compared

- Evidence: there is no snapshot, Copy Frame, Save Frame, contact sheet, or compare-two-frames
  command, despite decoded frames already existing in memory.
- Next: add current-frame copy/save with explicit coded/display transform and color policy, then a
  bounded contact sheet for a selected range.
- Complete when: output names source timestamp/frame, decoded pixel format, transform, color
  conversion, and subtitle inclusion; contact-sheet sampling is configurable and cancellable; and
  two frames can open in the image comparison surface.
- Related: B-101, B-104

### B-128 — Playback position and track choices are not resumed safely

- Evidence: closing or replacing a video loses time, rate, volume/mute, audio/subtitle track,
  subtitle settings, and view transform. Blindly restoring by path would apply stale time to a
  replaced file or resume near credits without consent.
- Next: specify media state fields, stable stream matching, identity checks, completion threshold,
  and privacy controls on top of B-043.
- Complete when: opted-in resume restores a compatible position and tracks, completed media restarts
  according to policy, replacement identity clears stale state, and one action forgets history.
- Related: B-043

### B-129 — Video decode and presentation have no selectable performance path

- Evidence: the detail line explicitly says `Swag CPU`; there is no hardware-decoder path, GPU
  upload/presentation mode, dropped/late frame counter, decode queue telemetry, power policy, or
  graceful switch when one path fails.
- Next: expose timing/queue diagnostics first, then define a hardware decode and zero/minimal-copy
  presentation boundary without changing codec correctness contracts.
- Complete when: the active decoder/render path and fallback reason are visible, dropped/late frames
  and A/V drift can be monitored, hardware output is validated against CPU reference frames, device
  loss recovers, and a deterministic CPU mode remains selectable.

This backlog covers playback, fallback presentation, and real-device validation owned by the
Swag Scope video viewer. Codec and container implementation work remains in [video.md](video.md)
or [audio.md](audio.md); this file owns how those capabilities reach the application surface.

## Playback coverage and fallback

### B-464 — WebM and VP9/AV1 Matroska video cannot be played

- Intent: Matroska now plays H.264, H.265, or MPEG-4 Part 2 with selectable AAC-LC, AC-3, E-AC-3,
  DTS Core, FLAC, MPEG Layer III, Vorbis, or Opus tracks through a compact EBML block index. WebM,
  and Matroska streams carrying VP9 or AV1, remain unread.
  The container already retains timestamps, synchronization points, lacing, and payload offsets;
  what remains is picture and sound codec support rather than another container design.
- Complete when: the `Video` viewer shows the picture with transport, a seekable timeline and the
  frame position for VP9 or AV1 in WebM and Matroska, and the registry moves those extensions off
  the binary line for playback while B-459 keeps the structure reader available as a second
  viewer. Opus and Vorbis use `std/audio` and stay synchronized with the picture.
- Related: B-459

### B-568 — An unsupported picture codec hides sound tracks the application can play

- Intent: a container currently fails as a video document when its picture codec is unavailable,
  even if one of its sound tracks has a registered decoder. The measured library exposes this with
  its single RV40 film; future partial codec coverage must not turn supported audio into no output.
- Complete when: Swag Scope offers a sound-only view for every decodable track when no picture
  track can be decoded, states that the picture is unavailable, and keeps ordinary video playback
  unchanged when both sides are supported.
- Related: B-565 in [video.md](video.md)

## Real-device validation

### B-633 — Audio-to-video synchronisation has never been observed against a real output device

- Area: apps/swagscope
- Found while: B-526, after the video viewer started presenting against the audio clock.
- Observation: the viewer presents each picture at the time the sound has reached, and nothing has
  yet confirmed that the time the sound reports is the time it is playing. On this machine the
  played-sample counter of a source voice stays at zero for a whole run even with buffers queued
  and the voice started, so the position `Voice.playbackPositionSeconds` answers never moves and
  the correction the player applies to its own clock never fires. Sound is audible on the user's
  machine, so the counter is expected to advance there; here it does not, and the difference is
  most likely that this process gets no working audio endpoint.
- Evidence: a temporary probe in the video viewer logging `activeDriverKind`, `buffersQueued`, and
  the raw played-sample counter once per second. Driver 2 (XAudio2), `queued=2` from the first
  second — so the source is primed and submission works — with `samplesPlayed` flat at zero
  twenty seconds in, from the start of the file and after a seek. Presentation is unaffected
  because playback keeps its own clock and only lets the sound correct it, which is what the last
  test of `viewer.video.test.swg` pins down.
- Next: play a video with sound on a machine whose output is audible and log
  `playbackSampleFrame` against the wall clock for a minute.
- Complete when: the sample cursor tracks real time, `followAudioClock` corrects a deliberately
  skewed video clock, and the 0.1 s dead band is shown not to cause visible stutter.
