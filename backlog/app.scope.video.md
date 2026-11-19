# Swag Scope Video Viewer Backlog

The Video viewer already performs progressive decode, frame-accurate indexed presentation for its
supported codecs, audio-clock synchronization, track selection, sidecar and embedded subtitles,
seeking, full-screen hosting, mute, and volume. This backlog owns professional playback and
inspection around `std/video`; codec implementation work remains in [std.video.md](std.video.md).

### app.scope.video.001 — Playback rate stops at 2x and has no pitch-preserving mode

- Evidence: the transport's playback-speed menu and Shift+Left/Right offer 0.25x–2x pitch-following
  rates through `Voice.setFrequencyRatio`; the silent clock scales with the rate, time labels stay source-time
  based, and the footer declares a non-1x rate, as it does under a recording. 2x is the XAudio2 default frequency-ratio
  ceiling. There is still no rate above 2x, no pitch-preserving mode, and no indication of the
  frame-drop/duplication policy.
- Next: decide the above-2x path — a voice created with a larger
  maximum frequency ratio, or software resampling — leaving pitch preservation explicitly
  unavailable until implemented.
- Done when: rate is keyboard adjustable, rates above 2x are offered or explicitly declined,
  A/V sync and subtitle timing hold at supported rates, frame scheduling declares drops, and reset
  returns exactly to 1x.

### app.scope.video.016 — Audio-to-video synchronisation has never been observed against a real output device

- Evidence: the viewer presents pictures at the time the sound reports, correcting its own
  clock with `followAudioClock`. A diagnostic run saw XAudio2's played-sample counter stay at
  zero with buffers queued, so `Voice.playbackPositionSeconds` never moved and the correction
  never fired; that run did not establish whether the process had a working audio endpoint.
  Only the no-sound stalled-output case is tested (`src/tests/cases/functional/viewers/video/video.swg`).
- Next: play a video with sound on a machine whose output is audible and log
  `playbackSampleFrame` against the wall clock for a minute.
- Done when: the sample cursor tracks real time, `followAudioClock` corrects a deliberately
  skewed video clock, and the 0.1 s dead band is shown not to cause visible stutter.

### app.scope.video.003 — Video cannot mark or loop an A/B range

- Evidence: the host's shared playback mode can loop the whole file. `[` and `]`, or the lens, mark
  where a looped passage starts and ends at the playback position (an end alone loops from the
  beginning); past its end, playback seeks back to its start through the ordinary seek pipeline,
  not as a jump to undo, and the timeline shows the passage as a band and the footer names it.
  The points cannot be set by pointer or timecode, the footer writes them in whole seconds, and
  there is no play-once selection or duration readout.
- Next: reuse the source-time range contract from app.scope.audio.002 on the video clock and seek pipeline.
- Done when: A/B can be set by pointer, timecode, or current frame; looping accounts for decode
  preroll without showing earlier pictures; subtitles/audio repeat in sync; and clearing the range
  restores normal end behavior.
- Related: app.scope.audio.002

### app.scope.video.012 — Media identity and track choices are not resumed safely

- Evidence: subtitle appearance persists globally. Reload and the home's saved per-file resume
  points retain time, rate, volume, mute and subtitle delay through `ViewerReadingState`, but
  selected audio/subtitle tracks and manual attachments are not restored. Resume points match
  paths without a media fingerprint, so replacing a file can apply an old reading state to new
  content. The home already offers explicit resume or restart and excludes near-start and
  completed media from its resume points.
- Next: add stable stream matching, attachment ownership and media identity checks to the
  existing reading state, preserving its completion threshold and privacy controls.
- Done when: opted-in resume restores a compatible position and tracks, completed media restarts
  according to policy, replacement identity clears stale state, and one action forgets history.
- Related: app.scope.viewers.003

### app.scope.video.006 — Video geometry has no explicit transform controls

- Evidence: frames honor the decoded display size through `ImageView.setDisplaySize`. The embedded
  ImageView already supports wheel zoom, drag pan, and double-click fit/actual size. The viewer has
  no explicit geometry inspector or controls for sample/display aspect overrides, rotation, clean
  aperture, crop, mirroring, or stretch policy.
- Next: separate coded size, clean aperture, display transform, and temporary view transform, then
  expose Fit, Fill, Actual Pixels, and declared-aspect modes.
- Done when: source and effective geometry are visible, rotation/mirror/aspect overrides are
  reversible, pan/zoom is bounded, subtitle placement follows display geometry, and screenshots
  use the chosen explicit transform.

### app.scope.video.009 — Audio synchronization and channel output cannot be inspected or corrected

- Evidence: subtitle delay is adjustable, but audio delay is not. Track entries and the information
  panel already show encoding, channels, sample rate, names and languages. Channel layout, downmix
  matrix, default/forced flags, loudness and A/V drift remain hidden.
- Next: expose audio-track metadata and measured clock drift, then add reversible audio delay and
  diagnostic channel/downmix selection.
- Done when: delay adjusts in fine and coarse steps, current drift and selected layout are
  visible, track flags/language/title are preserved, downmix policy is inspectable, and reset returns
  to container timing.
- Related: app.scope.video.016, app.scope.audio.005

### app.scope.video.013 — Video decode and presentation have no selectable performance path

- Evidence: the detail line explicitly says `Swag CPU`. Planar frames already reach
  `ImageView.updateVideoFrame` for renderer-side conversion, while packed frames use
  `exchangeImage`. There is no hardware-decoder selection, copy-cost telemetry, dropped/late
  frame counter, decode queue panel, power policy or graceful decoder-path fallback.
- Next: expose timing/queue diagnostics first, then define a hardware decode and zero/minimal-copy
  presentation boundary without changing codec correctness contracts.
- Done when: the active decoder/render path and fallback reason are visible, dropped/late frames
  and A/V drift can be monitored, hardware output is validated against CPU reference frames, device
  loss recovers, and a deterministic CPU mode remains selectable.

### app.scope.video.010 — Track and stream metadata have no complete media-information panel

- Evidence: the information panel presents picture/display size, FPS, frame count, duration,
  and the available audio/subtitle track names, languages, and encoding properties.
  Container brands, duration provenance, bitrate, time base, frame-rate mode, codec profile/level,
  pixel format, track IDs, disposition flags, tags, attachments, chapters, and decoder warnings are not
  presented together.
  [File Viewer Plus 7](https://fileviewerplus.com/support/video_files) offers a media information panel.
- Next: extend the existing panel with a complete container/stream metadata tree without coupling
  it to transport widgets. Start with one file containing several audio and subtitle tracks
  and check that each fact names its stream and source.
- Done when: container plus every stream has exact technical metadata and original tags,
  derived values identify their source, attachments open safely, warnings link to track/time where
  possible, and the report can be copied/exported.
- Related: app.scope.viewers.006

### app.scope.video.002 — Exact frame addresses and decode boundaries are not exposed

- Evidence: Left/Right seek by ten seconds, Ctrl+Left/Right step one frame and pause playback when
  needed. The clickable time and Ctrl+G accept absolute timestamps or signed seconds through
  presentation-time seeking. A reader cannot address a presentation frame/index or inspect
  keyframe versus decoded-frame boundaries.
- Next: add a numeric frame address and expose keyframe/preroll information where the container
  provides it, preserving source-time interpretation for variable-frame-rate streams.
- Done when: previous/next frame reaches the exact display order, numeric time and frame jumps
  validate their interpretation, variable-frame-rate content never invents a constant mapping, and
  the current PTS/DTS/keyframe state is inspectable.

### app.scope.video.004 — Chapters, editions, markers, and full seek history are absent

- Evidence: container chapters and Matroska editions are not surfaced. Return Before Last Jump
  restores one deliberate seek's source position; repeated seeks have no back/forward history
  or temporary bookmarks.
- Next: normalize container chapters/editions and sidecar chapter files into a landmark track,
  followed by session bookmarks and navigation history.
- Done when: chapter list, previous/next, edition selection, temporary named markers, and
  back/forward preserve exact times; invalid/overlapping chapters warn; and bookmarks export without
  modifying the video.

### app.scope.video.005 — Timeline seeking has no thumbnails or buffered/decode-cost feedback

- Evidence: dragging shows a time position only. There is no hover/scrub thumbnail, keyframe marks,
  buffered range, pending-seek state, decode distance, or distinction between exact and approximate
  seek.
- Next: build cancellable thumbnail tiles at keyframe-spaced landmarks with a strict memory and CPU
  budget, then annotate pending and ready ranges.
- Done when: hover and keyboard scrubbing preview nearby frames, obsolete requests cancel,
  exact versus approximate results are labelled, sparse indexes remain usable, and playback has
  priority over thumbnail work.

### app.scope.video.007 — Color, HDR, range, chroma, and deinterlace decisions are invisible

- Evidence: the information panel names the codec but not matrix, primaries, transfer, full versus
  limited range, chroma location, bit depth, HDR metadata, tone mapping, or interlace handling.
  std.video.006 covers missing interlaced H.264 decode, not the viewer controls and diagnostics.
- Next: surface stream color/interlace metadata and conversion path, then add safe temporary
  override and comparison controls as the video/pixel pipelines support them.
- Done when: source and output color facts are inspectable, unspecified values state defaults,
  HDR/tone-map and deinterlace modes are explicit, overrides reset cleanly, and a test chart verifies
  range and matrix handling.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.003, std.video.006

### app.scope.video.008 — Attached subtitles have no full track-management workflow

- Evidence: same-stem sidecars are discovered; arbitrary supported files attach from the track
  menu or a drop on the picture. One manual attachment replaces the previous one after successful
  decoding. Timing belongs to the film's reading state. There is no explicit reload after edit,
  detach, encoding override, multiple simultaneous tracks, preferred-language policy, safe-area
  guide, or list of parse warnings.
- Next: add reload and detach to the existing attachment workflow, then a subtitle-track manager
  reusing the standalone viewer's diagnostics.
- Done when: arbitrary supported sidecars can be attached/reloaded/detached, encoding and FPS
  policy are visible, primary and secondary tracks can coexist, parse warnings link to cues, and
  language preference persists without hiding other tracks.
- Related: app.scope.subtitle.002, app.scope.subtitle.003

### app.scope.video.011 — A frame cannot be copied, saved, or compared

- Evidence: Copy Frame, in the lens and on Ctrl+C, decodes the picture on screen again on a worker
  with a reader of its own, since the queue does not keep a picture once drawn, and puts it on the
  clipboard at the display size, scaled bilinearly from the coded size when they differ and
  without subtitles. The lens also copies the instant playback stands at, as the clock writes it,
  for the film and for a recording. The picture copy carries no timestamp or frame number, and there is no Save Frame,
  contact sheet or compare-two-frames command.
- Next: add current-frame copy/save with explicit coded/display transform and color policy, then a
  bounded contact sheet for a selected range.
- Done when: output names source timestamp/frame, decoded pixel format, transform, color
  conversion, and subtitle inclusion; contact-sheet sampling is configurable and cancellable; and
  two frames can open in the image comparison surface.
- Related: app.scope.image.006, app.scope.image.009

### app.scope.video.015 — An unsupported picture codec hides sound tracks the application can play

- Evidence: a container fails as a video document when its picture codec is unavailable (for
  example RealVideo RV40), even if one of its sound tracks has a registered decoder.
  [File Viewer Plus 7](https://fileviewerplus.com/open/webm) documents WebM playback. The VP9
  and AV1 decode work for that family belongs to std.video.010 and std.video.011.
- Next: when no picture track decodes, open the decodable sound tracks through the Sound
  viewer path and state that the picture is unavailable.
- Done when: Swag Scope offers a sound-only view for every decodable track when no picture
  track can be decoded, states that the picture is unavailable, and keeps ordinary video
  playback unchanged when both sides are supported.
- Related: std.video.010, std.video.011

### app.scope.video.017 — First-frame waits can stall during a full viewer session

- Evidence: the H.264 replacement scenario in `viewers/video/video.swg` can remain open with
  `awaitingFrame` true, playback stopped and no failure message during a full headless application
  selection. The same video file's focused tests can complete successfully in a fresh process.
- Next: reproduce the preceding viewer/decoder lifecycle and inspect first-frame publication,
  cancellation and scheduler ownership; retain the full-session ordering in the regression.
- Done when: repeated opens always publish a frame or a bounded failure, no first-frame wait
  leaves unfinished decoder work behind, and both isolated and mixed-viewer sessions finish.
