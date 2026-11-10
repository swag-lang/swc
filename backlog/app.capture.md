# Swag Capture Backlog

This file records the product outcomes and investigations for Swag Capture, including its
use of shared `bin/std` facilities.

Evidence, investigations, and intended outcomes owned by the application stay together here.
Operating-system work belongs in [platform.portability.md](platform.portability.md); compiler and language work
belongs in [compiler.core.md](compiler.core.md) and [language.design.md](language.design.md).
[README.md](README.md) has the whole layout.


## Entries

Swag Capture is the universal capture, as Swag Scope is the universal viewer: one gesture aims at
a screen, a window, an area or an area anchored to a window, one key chooses what is kept (picture,
animation, video, sound, scrolling page), and the same editor annotates the result. A capture is a
timeline; a picture is a timeline of zero length. The animated GIF is the first timed medium:
it carries the whole interaction and document change with short, bounded recordings, before video
(app.capture.011) and sound (app.capture.013) add their encoders. The proof of concept records, plays, saves and copies animations; native
Windows verification of the recording-control exclusion remains in app.capture.030.

Recordings of several hours are a requirement from the first timed medium on, even though the GIF
itself stays short: the recorded media is an append-only file written while recording and only
referenced by the capture document, so a save never rewrites it; no memory grows with the
duration; and the timeline, trimming and export work from indexes and streams, never from a
whole recording loaded at once.

### app.capture.039 — Remove global app dependencies from attached capture content

- Evidence: native user journeys with an independently owned `Gui.Application` found that `Capture.toImage`, capture texture cleanup, and `FormText.resolveFace` read the global `g_App` instead of their attached view's app. Those paths now use the view when attached, but `FormImage`, `FormStep`, and `BaseForm` still read `g_App` for rendering or theme resources.
- Next: audit each remaining global app access in forms and capture content, then move attached rendering and theme lookup to the owning view while preserving detached model behavior.
- Done when: all attached capture forms render and release resources in an independent native application, with no global renderer or theme dependency.

### app.capture.009 — Let users rebind capture hotkeys and resolve conflicts

- Next: persist shortcut choices in the existing options and add a conflict-resolution flow for
  combinations already owned by another application.
- Done when: users can rebind every capture command, conflicts identify the unavailable shortcuts,
  and the chosen bindings survive restart.
- Related: app.capture.010

### app.capture.015 — Assembling complete captures has no layout command

- Evidence: `Capture.paste` inserts clipboard images or form groups into the active canvas with
  remapped group identities and undo, but no command places several saved captures, each with
  its background and editable annotations, on a canvas sized for the composition.
- Next: add a complete-capture assembly command with explicit ordering, spacing and canvas
  bounds, built on the existing form model as one undoable operation.
- Done when: chosen captures land in order on a fitted canvas, their annotations stay editable,
  and one undo restores the previous canvas. Named reusable layouts remain app.capture.016.
- Related: app.capture.016

### app.capture.019 — A combined move-and-resize across monitors may kill Swag Capture

- Evidence: from a maximized window on a two-monitor desktop with different scales,
  `SetWindowPos(hwnd, HWND_TOPMOST, 40, 40, 2400, 1500, 0)` killed the packaged process in
  three of four attempts; move-only (`SWP_NOSIZE`) and hand-dragging never did. `Surface` now
  separates application placement from interactive `WM_DPICHANGED` and skips minimized
  `WM_SIZE`, but `surface.resize.swg` does not cover the maximized mixed-DPI transition and
  the crash has not been reproduced on the current implementation.
- Next: from the maximized two-monitor state, reproduce with the `gui2` example, then bisect
  move-only across the DPI boundary, resize-only on one screen, and both. Move the entry to
  [std.gui.md](std.gui.md) if the defect lands in `Surface`.
- Done when: the combined call survives repeated runs from the maximized mixed-DPI state with a
  regression test at the owning boundary, or the current `Surface` is shown not to reproduce it.

### app.capture.021 — Loading a capture blocks the interface during decode

- Evidence: `RecentView.select` in `src/recentwnd.swg` flushes a pending save of the selected
  file, then calls `Capture.load` synchronously on the interface thread, although the recent
  strip already has its preview. A 2341x1903 BGRA8 capture took a few hundred milliseconds on
  that path.
- Next: make selection an owned asynchronous load that leaves the preview visible, respects
  outstanding saves, and publishes only the result of the latest selection. Define cancellation,
  failure presentation and window-close cleanup before moving the decode off the interface thread.
- Done when: delayed loads cannot freeze input or replace a newer selection, failed loads
  leave a useful preview and diagnostic, and shutdown joins outstanding work.
- Related: app.capture.024, app.capture.025, language.parallelism.001

### app.capture.024 — Revisiting a recent capture decodes its full image again

- Evidence: `RecentView` retains previews and zoom state in `src/recentwnd.swg`; selecting an
  inactive item calls `Capture.load` again. The historical library sample averaged 7 MB of decoded
  pixels per capture and reached 47 MB, so retaining every decoded capture is not a bounded policy.
- Next: define a decoded-capture cache bounded by bytes, with ownership of the active editable
  capture, save completion and on-disk replacement included in its invalidation contract.
- Done when: revisiting an unchanged cached capture avoids decode, a modified/replaced file
  cannot reuse stale content, and the cache obeys its byte bound after selection and eviction.
- Related: app.capture.021

### app.capture.025 — Capture image chunks have no measured alternative to deflate

- Evidence: capture persistence uses `Core.Scc` deflate chunks. On a large photographed capture,
  BestSpeed stored 17.0 MB as 12.8 MB and slower levels gained only 0.3 MB more. This motivates a
  codec decision, not a format migration without a representative corpus.
- Next: compare stored and faster lossless chunk encodings on the same capture corpus, recording
  decode CPU, peak memory and file size. Keep existing files readable through their codec id.
- Done when: a documented selection rule has measured benefits on representative captures,
  and any new encoding round-trips with compatibility tests for existing deflate files.
- Related: app.capture.021

### app.capture.002 — No capture-level effect pipeline

- Evidence: `Capture` has geometry, a background image and forms, but nowhere to store and
  order capture-level effects; only individual forms carry a shadow.
- Next: add an ordered effect list to `Capture`, applied by one routine shared by preview,
  flatten and export, with its property panel generated through the reflective editor system.
- Done when: a stored effect renders identically in preview, flatten and export, survives save
  and reload, and is edited through the property panel.
- Related: app.capture.003, app.capture.005, app.capture.007, app.capture.008, std.pixel.012

### app.capture.001 — Print the current capture

- Next: once the GUI pagination/preview contract exists, add actual-size, fit-to-page and
  centered printing through it and Pixel vector output, not an application-only print path.
- Done when: each mode prints the capture with its annotations, and a page that would clip the
  capture warns before printing.
- Related: std.gui.030, std.pixel.005, std.gui.034

### app.capture.004 — No capture drop-shadow effect

- Next: add a drop shadow with offset, blur, spread and color through Pixel's effect graph, as
  an app.capture.002 effect.
- Done when: the shadow parameters are editable and render identically in preview and export.
- Related: std.pixel.012, app.capture.002, app.capture.003

### app.capture.003 — No capture border effect

- Next: add border width, color, placement and corner interaction as the first app.capture.002
  effect.
- Done when: each placement renders correctly with rounded and square corners in preview and
  export.
- Related: app.capture.002, app.capture.004

### app.capture.005 — No torn-edge capture effect

- Next: add deterministic torn-edge mask generation with scale-independent parameters as an
  app.capture.002 effect.
- Done when: the same parameters give the same edge at every zoom and export scale.
- Related: app.capture.002, app.capture.006

### app.capture.006 — No faded-edge capture effect

- Next: add a faded-edge mask as an app.capture.002 effect, independent of torn-edge generation.
- Done when: the fade width and edges are configurable and render identically in preview and
  export.
- Related: app.capture.002, app.capture.005

### app.capture.007 — No capture perspective effect

- Next: add a perspective transformation effect with explicit output bounds and resampling.
- Done when: the transformed capture fits its declared bounds and resamples identically in
  preview and export.
- Related: app.capture.002

### app.capture.008 — No capture watermark effect

- Next: add reusable image and text watermarks with placement, opacity and scale as an
  app.capture.002 effect.
- Done when: a watermark persists with the capture and appears identically in export.
- Related: app.capture.002

### app.capture.010 — No named capture presets

- Next: persist named combinations of capture mode, delay, cursor policy and destination in the
  options.
- Done when: a preset can be created, run, renamed and deleted, survives restart, and
  app.capture.009 can bind a hotkey to it.
- Related: app.capture.009

### app.capture.030 — Verify recording-control exclusion on Windows

- Evidence: the recorder follows an anchored window and pauses when it is hidden; X11 excludes
  a pill overlapping the area during root grabs, covered by an isolated-display test. Windows
  applies `WDA_EXCLUDEFROMCAPTURE` to the pill and frame, but that native path has not been run
  on a Windows desktop.
- Next: run a native full-screen recording on Windows and assert its frames contain neither the
  frame nor the pill, including a display where the pill overlaps the selected area.
- Done when: the Windows recording test passes and the controls remain usable throughout it.
- Related: platform.portability.097

### app.capture.038 — The kind menu still needs sound-only and scrolling capture

- Evidence: the in-place editor (`src/screenshot/inplaceeditwnd.swg`) now starts with one
  fixed-width kind menu, ordered by `KindMedia` in `src/screenshot/capturekind.swg`. Picture
  keeps its tools and Copy, GIF shows recording options with sound out of reach, and Video shows
  separate microphone and system-sound switches. Tab cycles the same three kinds. The menu
  leaves room for additional kinds without widening the bar. Sound alone and scrolling capture
  are not yet available.
- Next: add sound-only and scrolling capture to the kind menu when each can be taken, with its
  own options in the bar; keep the picture bar within a 1280-pixel logical screen.
- Done when: every kind Swag Capture can take is chosen from the bar of the zone, and the bar
  shows both sources of sound for a kind that records them.
- Related: app.capture.011, app.capture.013, app.capture.035

### app.capture.014 — A passage cannot be cut out of the middle of a recording

- Evidence: an animation keeps the part between an in point and an out point (`Capture.setTrim`,
  the brackets of the timeline), but a passage inside it cannot be removed.
- Next: add cut ranges inside the kept part, drawn and dragged on the timeline, skipped by playback
  and the export, as one undoable edit each; then the same for video.
- Done when: an export leaves out exactly the cut ranges, the timing of what follows is joined, and
  the stored recording is unchanged.
- Related: app.capture.011, app.capture.037

### app.capture.011 — No video recording

- Evidence: video recording is a product goal of the universal capture. The `Video.Writer`
  facade still writes Motion JPEG in MP4 and AVI, plus Y4M. Separately, pure Swag H.264 and
  AAC-LC encoders now feed a resumable fragmented-MP4 writer with video and sound tracks;
  `Video.Reader` and FFmpeg play their output. `Video.Mp4.SoftwareRecording` now joins the
  encoders, exact video frame slots, arbitrary PCM chunks, AAC priming and MP4 finalization.
  Synthetic static and scrolling 1080p60 sequences encode faster than real time in Release.
  A headless X11 integration test now grabs actual changing window pixels through
  `ScreenFrameSource`, encodes three frames (including a repeated one) with synthetic PCM16 into
  MP4, and reopens the H.264 pictures and AAC sound through `Video.Reader`.
  `VideoCaptureSession` now keeps a screen source, exact frame pacer and MP4 writer alive; X11
  tests cover sound input, repeated missed slots, source failure and recovery, and a black first
  frame before a source returns. A four-hour video interruption now uses one held MP4 picture
  instead of encoding 863,999 repeated frames; the reader seeks within its exact long duration.
  The X11 source uses native MIT-SHM through the existing XCB
  connection and reuses frame storage. Parallel 4K BGRA conversion improved acquisition from
  6.1–6.3 to 4.7–5.1 ms per image with full color parity; 1080p remains about 1.2 ms on its
  sequential path. An opt-in 4K60 test on a static Xorg dummy screen measured
  1.033–1.048 seconds for 60 screen grabs and encoded frames, with a 40,846-byte MP4;
  adding 48 stereo AAC packets took 1.282 seconds total. `Video.Reader` reopened the file in
  3.6 ms and decoded the last frame in 298 ms. This is a synthetic static scene just beyond
  real time. A separate X11 4K60 changing-screen test with AAC takes 2.75 seconds for 60
  capture/convert/encode/write operations (45.8 ms per image), plus 0.21 seconds for AAC, and
  produces a 99.2 MB MP4. `Video.Reader`, FFprobe and FFmpeg read both tracks; the output-sound
  test has no actual audio device. `VideoCaptureSession` accepts optional H.264 QP 0–51 and
  one through eight row-band slices, preserving exact QP 0 and one slice by default. On the
  same dynamic X11 4K60 scene, quantized QP 28 with four slices, motion residuals and
  P-slice Intra16x16 coding of flat regions took 2.40–2.93 seconds across earlier runs.
  A later portable flat-block row comparison reduced a paired run from 2.514 to 2.340
  seconds. Direct flat luma DC quantization moved one run to 2.289 seconds; a single-DC
  CAVLC path then reduced a paired run with the same AAC from 2.301 to 2.229 seconds,
  with a byte-identical MP4. The file is 4.159 MB after separate AAC section savings,
  at 48.41 dB final-frame luma PSNR. Flat P Intra now also supports QP 36: a current
  app run took 2.214 seconds, 3,180,677 bytes and 40.26 dB, compared with
  3.55–3.73 seconds, 10.06 MB and 38.10 dB on the earlier path. Reader and FFmpeg
  decode the 60 pictures and AAC. Exact QP 0
  with four slices and one matching diagonal motion vector takes
  1.37–1.51 seconds and produces 7.78 MB. These modes remain slower than the one-second
  4K60 target on this machine. `VideoCaptureSession` also
  checks the destination volume once per second, reserves 64 MiB by default, and finalizes
  the last playable MP4 prefix when free space falls below that threshold; an integration
  test reopens its final video and AAC tracks after the simulated stop. The nine X11
  integration tests passed before the last chroma shortcut; two later repeats stalled in
  the first generated X11 test at three and one workers. Temporary trace prints narrowed
  repeated direct-run timeouts to just before or within `Reader.decodeFramePlanesInto`:
  at two runtime workers, 4 of 12 and then 5 of 24 runs stopped between `Reader.open`
  and the first decoded picture, while 12 of 12 at one worker passed. Closing the X11
  fixture before decoding did not resolve it (5 of 24 timeouts). A temporary small-image
  reconstruction threshold did not resolve it (3 of 24 timeouts), but source inspection
  showed that this one-slice IDR already uses inline reconstruction, so that threshold
  did not test the parallel band pipeline. Limiting the tiny stream to one H.264 frame
  lane also left 3 timeouts in 48 direct runs at two workers. A separate run stopped
  before the test body. Deeper temporary markers gave 7 timeouts in 24 runs before
  `prepareAccessUnit` finished; a second 24-run pass gave 3 timeouts, one inside
  `handleNal` for the first IDR and two after frame submission while a decode worker
  was active. The point moves with instrumentation, so no H.264 or runtime root
  cause is proven. All diagnostic edits were removed. The intermittent test-runner
  or decode stall still needs isolation. Swag Capture now offers Video in the zone's kind menu and a Record Video
  command. The recording controls create an MP4 beside the capture document; the editor and
  library reopen its timeline. Save as Video copies an untouched recording, or renders its chosen
  span and timed annotations into a new MP4 while retaining the separate sound tracks. Library
  export writes MP4 for a video and GIF for an animation. Copy Video places the edited MP4 with
  sound on the clipboard as a file, including from the library. Pause remains unavailable for
  video. An opt-in Windows browser integration (`tools/capture-web.py`) exercises the persistent
  GDI source, native system loopback, saved-library reopen, every H.264 picture, a full editor
  playback loop and actual XAudio2 output. Its small web fixture does not establish large-area
  cadence or long-session behavior on Windows hardware. The GIF recorder's
  `RecordingClock` keeps monotonic session time with pauses removed.
  `TimelineBar.onTimerEvent` decodes synchronously through `Capture.showFrame`; a sampled
  random seek in a 1510x950 recording takes about 416 ms in a script probe, so a slow seek can
  block input and presentation independently of codec correctness.
- Next: measure Windows playback timer/decode delays;
  compare a bounded asynchronous picture queue with Swag Scope's reader if decode blocks the
  interface. Isolate the generated X11 test runner stall. Measure the persistent GDI source on
  Windows and use Desktop Duplication acquisition (platform.portability.097) only if the required
  cadence cannot be met, with pacing/repeated lost frames, a fragmented MP4 master (std.video.016),
  and readback through the existing H.264 decoder for the timeline and re-export.
  Long recordings need, beside the stream: a recording folder that may differ from the library,
  a visible low-space stop reason and optional automatic splitting by
  duration or size, and recovery when the source is lost (secure desktop, display change, GPU
  reset) by repeating the last frame and reacquiring instead of ending the recording.
- Done when: a four-hour recording of a 1080p monitor at 60 frames per second, and a 4K one at 60
  for an hour, produce playable MP4 files with memory independent of the duration and reported
  dropped frames; the recording continues across a lock screen, an elevation prompt and a display
  mode change; and the file stays playable after the process is killed mid-recording.
- Related: app.capture.013, app.capture.014, app.capture.034, app.capture.037,
  platform.portability.097, std.video.015, std.video.016

### app.capture.013 — Recordings cannot include audio

- Evidence: `Audio.CaptureQueue` now reports PCM timing, gaps, overflow and source restoration
  with bounded storage; software AAC and MP4 recording consume its output. A simulated
  microphone outage produces audible sound, silence, then sound in a decoded MP4. Native
  WASAPI microphone and system-output-loopback backends pass Windows semantic checks and
  simulated PCM conversion, loss, idle-silence and clock-drift tests. `VideoAudioPump` transfers
  two independent capture queues to separate MP4 tracks in bounded chunks, including a
  simulated four-hour source gap without generating all its silence in one call. App tests
  reopen the MP4 and check both decoded tracks before, during and after the gap, a bounded
  queue overflow, and live 96 kHz float source packets resampled into a 48 kHz MP4 track.
  Swag Capture now connects the native microphone and system-output-loopback backends to two
  separate tracks in its video recorder. The zone bar chooses each source independently; source
  loss inserts silence while a retry opens it again. The opt-in Windows browser integration
  verifies native system-output capture and editor playback by measuring a reference tone in a
  second WASAPI loopback while the browser is muted. Microphone-device execution and
  long-session sync still need verification. The editor timeline plays both recorded tracks
  and follows the first track's audio clock.
  GIF capture has no audio source or track.
- Next: measure audio/video drift over a long recording and correct any drift beyond one frame;
  then add a microphone level meter, an application-only sound source for window targets, and
  post-recording track levels on export. Add a sound-only medium with a waveform timeline when
  it supports a concrete capture workflow.
- Done when: a recording with sound stays within one video frame of sync over four hours, each
  source's level can be changed after recording, unplugging and replugging a device mid-recording
  leaves silence on its track instead of ending the recording, recording without any audio device
  still works, and a sound-only capture exports a playable file.
- Related: std.audio.011, std.audio.013, std.audio.015, std.audio.016, app.capture.011

### app.capture.034 — The cursor is burned into the recorded pixels

- Evidence: `drawCursorInto` in `src/screenshot/screenshot.win32.swg` paints the cursor into the
  grabbed pixels; Desktop Duplication delivers pointer shape and position separately.
- Next: keep the cursor as a track (position, shape, clicks) beside the frames. Burn it in at
  export by default, and offer a Studio choice that keeps a cursor-free master and edits the track
  afterwards: hide, enlarge, smooth, mark clicks, zoom towards clicks.
- Done when: one master exports with the cursor hidden, enlarged, or with clicks marked, in GIF
  and in MP4.
- Related: app.capture.011, platform.portability.097

### app.capture.035 — No scrolling capture

- Next: take successive frames of a window or area while it scrolls, by the reader's wheel or by
  synthetic input, register their overlap, and stitch one tall picture capture.
- Done when: long documents scrolled in a browser and in an editor stitch without seams or
  repeated rows, and an overlap that cannot be registered stops with a clear message.
- Related: app.capture.030

### app.capture.036 — No camera overlay

- Next: after app.capture.011, add a camera source (platform.portability.100) drawn as a movable,
  resizable overlay over the recording and kept as its own track until export.
- Done when: a recording with a camera overlay exports it where it was placed, and the overlay can
  be moved or hidden after recording.
- Related: app.capture.011, platform.portability.100

### app.capture.037 — Exporting a long recording re-encodes all of it

- Evidence: trimming, cutting and annotating an hours-long recording would otherwise re-encode
  every frame, which costs about as long as the recording.
- Next: export by packet copy (std.video.017) wherever nothing changes the pixels, and re-encode
  only the groups of pictures that a cut point, an annotation span, the cursor track or a crop
  touches, with matching encoder parameters.
- Done when: a trimmed three-hour recording with a few annotations exports in a small fraction of
  its duration, the result plays seamlessly across copied and re-encoded segments, and the stored
  recording is unchanged.
- Related: app.capture.011, app.capture.014, std.video.017

### app.capture.016 — No reusable capture layout templates

- Next: persist named layout descriptions produced by app.capture.015 and apply them to a new
  selection of captures.
- Done when: a saved template survives restart and reproduces its ordering, spacing and bounds.
- Related: app.capture.015

### app.capture.017 — Stamp library

- Next: design a reusable stamp set following `design-swag-identity` and place stamps as
  `FormImage` instances.
- Done when: stamps can be browsed and placed from the editor and remain editable images.

---
### app.capture.041 — Match library hints to the filtered result

- Evidence: the `library.empty-search.paper` golden shows no matching capture, while the hint line still offers Open, Delete, Rename, and Rate. Those actions have no target in this state.
- Next: derive the hint line from the filtered selection and retain only actions that can apply when the result is empty.
- Done when an empty search or filter shows no item actions, and clearing it restores the available selection hints.
