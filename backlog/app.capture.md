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
timeline; a picture is a timeline of zero length. The animated GIF is the first timed medium
(app.capture.012): it carries the whole interaction and document change with short, bounded
recordings, before video (app.capture.011) and sound (app.capture.013) add their encoders. The
order is app.capture.028, app.capture.029, app.capture.030, app.capture.012, then
app.capture.031, app.capture.032, app.capture.014 and app.capture.033.

Recordings of several hours are a requirement from the first timed medium on, even though the GIF
itself stays short: the recorded media is an append-only file written while recording and only
referenced by the capture document, so a save never rewrites it; no memory grows with the
duration; and the timeline, trimming and export work from indexes and streams, never from a
whole recording loaded at once.

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

### app.capture.028 — The capture document has no notion of time or media kind

- Evidence: `Capture` in `src/capture.swg` holds one `backImg` and `backImgOriginal`, a size, and
  forms without time; `CaptureLibraryMetadata` stores a size and a `CaptureSourceKind` only;
  `writeScc` in `src/capture.file.swg` writes model, background, original and preview chunks,
  and every save, automatic ones included, rewrites the whole container through `saveAtomic`.
  Nothing can hold frames, a duration or sound, and a recording of several hours could not live
  in a file rewritten by each save.
- Next: add a media kind (picture, animation, later video and sound) and an optional timeline
  (duration, frame rate, in and out points, tracks) to the document and to the library metadata.
  Keep timed media out of the SCC rewrite: the recording is an append-only media file beside the
  capture, referenced with its identity (size, hash of its header, duration) the way
  `linkedImage` references a picture, and moved, trashed and restored with it by the library.
  Read it through one frame source by time with a seek index, the picture being its zero-length
  case. Keep the canvas painting `backImg`, refreshed from the frame at the playhead, so the
  editing paths stay shared. Raise `CaptureProfileVersion` and keep version 1 files loading as
  pictures.
- Done when: a picture capture saves and loads unchanged; an animation capture round-trips its
  timing and forms while saving it leaves its media file untouched; a missing or replaced media
  file is reported instead of being read; and the library reads media kind and duration from the
  profile without opening the media.
- Related: app.capture.012, app.capture.029, app.capture.031, app.capture.032, app.capture.037

### app.capture.029 — The capture overlay produces a picture instead of a target

- Evidence: `screenShot` and `performScreenCapture` in `src/screenshot/screenshot.swg` grab the
  frozen desktop, let the reader aim on it, then crop straight into `Capture.backImg`. The chosen
  window (`g_CaptureWindow`) is only metadata, and `CaptureMode` mixes what is aimed (area,
  monitor, window) with how it is taken.
- Next: make the overlay return a capture target (monitor, window, free area, or area anchored to
  a window as an offset in its frame) and hand it to an acquisition chosen with one key (`Tab`:
  picture, animation, later video, sound and scrolling), remembered between captures. Keep the
  frozen desktop for aiming; let `getCaptureWindowForRect` anchor an area drawn inside one window,
  with a key to detach it.
- Done when: every current picture mode goes through the target, the media key switches the
  acquisition before the capture starts, and an anchored area keeps its offset when its window
  moves.
- Related: app.capture.028, app.capture.030, app.capture.009

### app.capture.030 — No recording session, frame or start-stop hotkey

- Next: add a recorder state machine (armed, countdown, recording, paused, finishing, cancelled)
  driving a timed acquisition worker clocked on the performance counter. While recording, draw a
  thin frame just outside the target and a small pill beside it (elapsed time against the limit,
  pause, stop, cancel), both outside the captured pixels. The hotkey that starts a recording stops
  it (`Shift+PrintScreen` proposed). A window-anchored target follows its window and pauses while
  it is minimized.
- Done when: a recording starts, pauses, resumes, stops and cancels from the pill, the keyboard
  and the global hotkey; neither the frame nor the pill appears in the frames; and stopping opens
  the result in the editor.
- Related: app.capture.029, app.capture.012

### app.capture.012 — No animated GIF recording

- Evidence: the first timed medium. It exercises app.capture.028 through app.capture.033 with the
  existing `BitBlt` acquisition, whose cost follows the grabbed area, and needs no new platform
  binding, so it validates the interaction and the document before video encoders exist.
- Next: record into an append-only frame file streamed to disk by a writer thread behind a bounded
  queue: a lossless key frame about every second, then only the rectangle changed since the
  previous frame, each timestamped, with a seek index. It follows the media contract of
  app.capture.028, so the limits below are a property of the GIF medium, not of the store: 10, 15
  or 20 frames per second (15 by default), 30 seconds by default and 60 at most, and a maximum
  stored dimension. Export through std.pixel.image.051 with looping and frame delays taken from
  the timestamps.
- Done when: memory stays flat while recording and the same store, run without the GIF limit for
  an hour in a test, keeps memory flat and seeks to any instant in bounded time; the export
  decodes back through Pixel's GIF decoder with the same frame count and timing; and dropped
  frames are reported.
- Related: app.capture.011, app.capture.028, app.capture.030, app.capture.031, std.pixel.image.051

### app.capture.031 — The editor has no playhead

- Next: show a thin timeline under the canvas for a timed capture only: play and pause,
  scrubbing, frame stepping (`Space`, `Left`, `Right`), elapsed and total time, every command also
  in the lens. The canvas shows the frame at the playhead. A picture shows no timeline. Scale it
  from seconds to hours from the start: zoom around the playhead, markers, thumbnails decoded
  lazily for the visible range only, and seeking through the media index.
- Done when: an animation can be played, scrubbed and stepped, a synthetic recording of several
  hours scrubs and zooms without decoding outside the visible range, the picture editor is
  unchanged, and goldens cover both, each in one palette.
- Related: app.capture.028, app.capture.032, app.capture.014

### app.capture.032 — Annotations have no time span

- Evidence: `BaseForm` and the form models serialize no time, so on a timed capture every form
  would show for the whole duration.
- Next: give every form a span (start and end, the whole capture by default), shown on the
  timeline for the selected form and set from the playhead (`[` and `]`), and honored by the
  canvas and every export. Crop and flatten of a timed capture stay non-destructive across frames.
- Done when: a form shows only inside its span in the editor and in the exported GIF, spans
  survive save, reload and undo, and picture captures keep their current behavior.
- Related: app.capture.028, app.capture.031

### app.capture.014 — Recordings cannot be trimmed in the editor

- Next: add non-destructive in and out points, then cut ranges, on the app.capture.031 timeline,
  for animations first and video next, and export only what is kept.
- Done when: trimmed export contains exactly the chosen ranges and the stored recording is
  unchanged.
- Related: app.capture.031, app.capture.012, app.capture.011, app.capture.037

### app.capture.033 — Timed captures are invisible in the library and the output gestures

- Evidence: `Library.enumerateSupportedFiles` lists SCC captures and loadable images, so an
  animated `.gif` opens as one picture. The strip's primary action copies a picture through
  `Clipboard.addImage`, and the clipboard cannot publish a file (std.gui.063).
- Next: mark timed captures in the recent strip and the library (duration badge, a media facet
  in the filters), open an animated GIF as an animation capture, and make Copy and Save follow
  the media: picture formats for a picture; GIF, later APNG and MP4, for an animation, copied as a
  file.
- Done when: an animation can be found by media in the library, a dropped animated GIF opens with
  its frames, and Copy puts the exported GIF on the clipboard in a form that Explorer and
  messaging applications accept.
- Related: app.capture.012, app.capture.028, std.gui.063, std.pixel.image.052

### app.capture.011 — No video recording

- Evidence: video recording is a product goal of the universal capture. `Video.Writer` writes
  only Motion JPEG in MP4 and AVI, plus Y4M, with no sound track, and `BitBlt` acquisition cannot
  sustain large areas at 60 frames per second.
- Next: once app.capture.012 has proven the session, timeline and document, add video as a
  medium: Desktop Duplication acquisition (platform.portability.097), H.264 encoding
  (std.video.015), and a fragmented MP4 master (std.video.016) read back by the existing H.264
  decoder for the timeline and re-export.
  Long recordings need, beside the stream: a recording folder that may differ from the library,
  free-space watching that stops cleanly before the disk is full, optional automatic splitting by
  duration or size, and recovery when the source is lost (secure desktop, display change, GPU
  reset) by repeating the last frame and reacquiring instead of ending the recording.
- Done when: a four-hour recording of a 1080p monitor at 60 frames per second, and a 4K one at 60
  for an hour, produce playable MP4 files with memory independent of the duration and reported
  dropped frames; the recording continues across a lock screen, an elevation prompt and a display
  mode change; and the file stays playable after the process is killed mid-recording.
- Related: app.capture.012, app.capture.013, app.capture.014, app.capture.034, app.capture.037,
  platform.portability.097, std.video.015, std.video.016

### app.capture.013 — Recordings cannot include audio

- Next: after app.capture.011, add the dock toggles: microphone with its level meter, system
  sound, or this application's sound only for a window target. Keep each source on its own track,
  timestamped on the performance counter and mixed only at export. Add a sound-only medium with a
  waveform timeline.
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
- Related: app.capture.011, app.capture.012, platform.portability.097

### app.capture.035 — No scrolling capture

- Next: take successive frames of a window or area while it scrolls, by the reader's wheel or by
  synthetic input, register their overlap, and stitch one tall picture capture.
- Done when: long documents scrolled in a browser and in an editor stitch without seams or
  repeated rows, and an overlap that cannot be registered stops with a clear message.
- Related: app.capture.029, app.capture.030

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
- Related: app.capture.011, app.capture.014, app.capture.032, std.video.017

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
