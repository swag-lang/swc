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

- Evidence: All recent selections, including library opens, explicit file opens, deletion
  replacements and the first startup document, now decode through an owned background task.
  The outgoing edited capture is snapshotted before switching and saved on a worker. Inactive
  metadata edits and rename now queue a worker rewrite of only the model and SCC header, copying
  the stored image chunks exactly. Consecutive edits and automatic saves share one writer lane,
  so the interface does not wait for model form decoding or file replacement. Full `Capture.load`
  has been removed from library Save as Image: the file dialog chooses a destination, then an
  owned worker loads the full document before composition. For still images, the interface renders
  the pixels and a second worker encodes and atomically replaces the output. Duplicate rewrites the
  model on a worker while copying stored image chunks and timed-media files, and refreshes an
  already-open library when complete. Duplicating the active editor now snapshots its unsaved
  model and images at the click, then writes the new SCC and copies timed media on a worker;
  the original keeps its dirty state for its normal save. Library Copy and selected-library
  Export also decode on
  workers. Exporting an unchanged video from the editor, an individual library selection or a
  selected-library batch now copies its MP4 on a worker and publishes it atomically, without
  borrowing the editable capture. The batch waits for each copy before reporting completion. Image
  composition and timed-media encoding for edited captures still run on the interface thread.
  A 2341x1903 BGRA8 capture took a few hundred milliseconds on the old full-load path.
- Next: move timed-media copy/export encoding away from the interface where renderer ownership
  permits. Preserve save ordering and failure reports.
- Done when no user action decodes an inactive capture on the interface thread, and cancel,
  failure and window-close paths release each background result.
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

- Evidence: X11 excludes a pill overlapping the area during root grabs, covered by an isolated
  display test. Windows applies `WDA_EXCLUDEFROMCAPTURE` to the pill and frame; the native browser
  integration now checks that Windows accepted affinity `0x11` for the pill, and that the pill
  overlaps the selected virtual desktop when all screens are recorded. Its last decoded frame
  was visually inspected without recording controls. The scenario still does not assert their
  removal from captured pixels. Video target visibility and sound servicing remain
  app.capture.011/app.capture.013.
- Next: the native full-screen runner now records one monitor and the virtual desktop; assert
  that its frames contain neither the frame nor the pill, including a display where the pill
  overlaps the selected area.
- Done when: the Windows recording test passes and the controls remain usable throughout it.
- Related: app.capture.011, app.capture.013, platform.portability.097

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

### app.capture.011 — Make two-hour video recordings reliable

- Evidence: `Recorder.recordVideo` has no duration limit and streams H.264/AAC into fragmented
  MP4 while recording. The writer bounds picture, PCM and packet storage; retaining an untouched
  recording needs a file copy rather than a final encode. `tools/capture-web.py` verifies actual
  Windows browser pixels, native system sound, saved-library reopen, every picture and a full
  editor playback loop with measured XAudio2 output. It accepts a native 1920x1080 browser source
  and a missed-slot budget. Six-second samples do not establish two-hour endurance or drift.
  The application fixes video capture at 30 fps and uses software H.264 with exact QP 0,
  bounded parallel slices and no target bitrate. Screen acquisition now runs on its own thread;
  a two-slot handoff overlaps it with video encoding while the interface handles controls and
  window tracking. WASAPI servicing and AAC encoding have separate bounded workers, with
  multimedia scheduling for the native source. A six-second Windows browser recording at
  1920x1080 with a forced 250 ms interface stall missed zero slots with both compiler executables;
  the previous interface-driven reader necessarily lost the slots during such a stall. At
  2304x1296, GDI short runs ranged from zero to 83 missed slots out of about 179. The new
  `Screen.Source` uses DXGI Desktop Duplication for Windows video and X11 MIT-SHM for Linux video;
  Windows keeps GDI as fallback. A 2304x1296 DXGI browser run with cursor, sound and a forced UI
  stall missed 11 slots while decoding all 179 frames and replaying sound without queue loss;
  another missed two. The native full-screen runner records a 3840x2160 monitor and a 7680x2169
  virtual desktop, with proportional H.264 output at 4096x1156 for the latter. Direct multi-output
  composition reduced its missed slots from 28 to five in one three-second run, though another
  missed 23. The source reports acquisition, readback and copy costs. These short runs do not
  establish sustained throughput; storage use, source losses and performance under sustained
  machine load still need measurement.
  Explicitly missed slots now use the encoder's fast held-picture path. The editor also decodes
  video directly into its reusable canvas image, avoiding a full-resolution RGB copy per shown
  frame. A subsequent three-second virtual-desktop run decoded its 85-frame MP4, missed five
  slots, and spent 29 µs in total on held-picture encoding. Fresh-picture encoding still took
  539 ms and screen acquisition/composition 2.09 seconds in that run.
  The recorder now uses the source's unchanged-pixel result to emit held pictures without
  BGRA scaling or a cached-image copy when the pointer is excluded. A native 3840×2160 monitor
  run decoded all 90 output frames, including five unchanged-source polls and six missed slots;
  the short run does not isolate a whole-pipeline gain because the displayed content and DXGI
  presentation rate varied between runs.
  Full-desktop captures now reduce bottom-up BGRA with parallel 32-bit nearest-neighbor copies;
  a large synthetic case matches both the serial and byte-copy references exactly. In one native
  7680x2169 desktop run, reduction took 228 ms for 86 output frames, compared with 510 ms in an
  earlier run before the parallel change. DXGI changed-region readback reduced CPU pixel copies
  in that native run to 68.7 million; the 4096x1156 MP4 decoded and missed five slots. A separate
  full-monitor run decoded 90 frames and missed one slot. A 1920x1080 browser-area run with sound,
  editor replay and a forced 250 ms interface stall decoded 179 frames and missed one slot. The
  scene and display activity varied, so these timings are diagnostic rather than a throughput
  guarantee.
  A new Windows full-screen pass captured a 3840x2160 monitor as 90 playable frames with four
  missed slots. A 7680x2169 virtual desktop rendered at 4096x1156 as 90 playable frames with
  three missed slots. With the cursor included, `ScreenFrameSource` now restores only the old
  pointer rectangle before asking DXGI to mirror changed desktop regions. It compares the new
  pointer pixels with the prior overlay so a stationary cursor can use a held picture. On one
  three-second virtual-desktop pass, composition fell from 285 ms to 9 ms, scaling from 180 ms
  to 20 ms, and fresh-picture encoding from 383 ms to 76 ms; both passes missed three slots.
  Desktop activity varied between passes, so this establishes the avoided full-frame copies,
  not a guaranteed end-to-end throughput gain.
  The Windows fixture now stays visible above unrelated desktop windows, and monitor tests
  target the display containing its moving video. A 3840x2160 monitor with a 3200x1800 moving
  browser scene missed one slot in 90 before setup was separated from the timeline. On the
  virtual desktop, the first screen grab took up to 161 ms and accounted for four early missed
  slots. The producer now acquires a frame before starting the pacer, and the HUD clock starts
  at the accepted video origin. A subsequent 3840x2160 monitor run and a 7680x2169 desktop run
  each had zero missed slots over 91 frames; both files lasted 3.033 seconds. A six-second
  1920x1080 browser-area run with sound and a 250 ms interface stall also had zero missed slots
  and replayed its audio. Another area run missed one slot, so sustained throughput and
  intermittent OS scheduling delays still need measurement. The HUD no longer blocks its
  interface thread while the producer primes DXGI; its clock remains at zero until the first
  accepted picture. The native browser journey and eight focused recorder tests cover that
  start sequence.
  A one-minute native run with a 3200x1800 moving browser scene on a 3840x2160 monitor
  produced 1801 frames over 60.033 seconds with zero missed slots and zero source failures.
  The maximum-detail QP 0 file was 1144 MiB. QP 18 produced 61.7 MiB with the same frame
  count and no missed slots, while a static browser-chrome strip differed by 0.58 of 255
  levels per color channel on average in three-second comparisons. QP 28 reached 2.2 MiB
  versus 3.2 MiB for QP 18 in those short runs; the same static strip differed by 1.50
  levels per channel on average. Swag Capture now defaults to Balanced (QP 18) and offers
  Maximum and Compact in capture options. A six-second 1920x1080 area recording at the new
  default retained continuous system sound through editor replay. It missed no frame slots
  despite a 250 ms interface stall. These measurements use a low-motion browser fixture;
  full-motion 4K and two-hour disk throughput still need measurement.
  A separate one-minute 7680x2169 virtual-desktop run with the pointer included encoded
  1801 frames at 4096x1156, missed no slots and produced 34.9 MiB with Balanced. The same
  fixture at Maximum had produced 480.1 MiB; changing desktop activity limits a precise
  ratio, but the size reduction is substantial.
  A separate full-viewport color-and-motion fixture changed nearly every sampled pixel
  between its first and last decoded 4K frames. At Balanced, a one-minute monitor recording
  missed 13 of 1801 slots, spent 55.4 seconds encoding, and wrote 400.6 MB; at Compact it
  missed one slot, spent 49.0 seconds encoding, and wrote 193.1 MB. The browser and desktop
  workloads varied, so these are stress evidence rather than a controlled QP speed ratio.
  Increasing the handoff queue from two pictures to four did not improve a subsequent run;
  it missed 60 slots while encoding consumed 59.3 seconds, so the queue was left unchanged.
  `recordVideo` now preserves a fragmented MP4 once frames exist, finalizes what it can after
  late producer or audio errors, and returns an editable capture when that prefix is readable.
  A failure toast exposes the retained file in the explorer. On startup and when the library
  folder changes, a serial background scan recognizes orphan `video-<capture-stem>.mp4` files,
  rebuilds SCC documents for readable prefixes in batches of four, and refreshes the library.
  A functional test recovers a flushed, unfinalized MP4; a native journey checks the recovered
  library entry.
  A separate-process termination/reopen run remains to be done.
  `VideoCaptureSession` inherits one video/AAC packet per fragment and no final random-access
  index. Two hours at 30 fps with one 48 kHz audio track means about 554,000 fragment headers.
  `Video.Reader` scans headers and builds sample tables when opening; the editor decodes on the
  interface thread. A sampled random seek in a 1510x950 recording takes about 416 ms.
  The low-space path checks once per second with a 64 MiB reserve and can finalize a prefix;
  sudden disk errors, source loss and process termination have not been verified as one native
  application lifecycle. Intermittent generated X11 test stalls remain unisolated around startup,
  H.264 access-unit preparation and decode workers; instrumentation changes their location.
- Next: add a separate-process termination/reopen scenario for recovery, including a fragment
  interrupted in mid-write. Then measure a moving 1080p30 browser source with audio under
  sustained load, select a bounded
  recording-quality policy, and reduce multi-monitor readback and copying through std.screen.002
  before promising 30 fps for large or multi-monitor areas.
  Group fragments within a stated recovery-loss budget, emit the final key-frame index and use
  it for fast opening/seeking through std.video.016. Preserve the resumable media prefix.
  Add an explicit two-hour native endurance runner with a visible time code and synchronized
  sound markers; sample drift, RSS, CPU, byte rate, free space, actual/repeated pictures and queue
  losses at the beginning, middle and end. Its checks must include recording stop, reopen, seeking
  near the end and playback. A short fixture loop and simulated timestamps are not that proof.
  Define the destination separately from the library, report a low-space stop visibly, and verify
  source/window loss and restoration without losing usable video or stopping sound servicing.
- Done when: a real two-hour 1080p30 browser recording with system sound remains responsive,
  keeps recording memory bounded, has no unreported losses, meets the drift bound in app.capture.013,
  stops without a whole-recording encode, and opens/seeks/plays promptly. Disk failure or process
  termination leaves the completed prefix recoverable. Higher-resolution/cadence encoder goals
  remain in std.video.015; native control-exclusion coverage remains app.capture.030.
- Related: app.capture.013, app.capture.030, app.capture.037, std.video.015, std.video.016,
  platform.portability.097, std.screen.004

### app.capture.013 — Keep recorded sound available and synchronized over long sessions

- Evidence: microphone and system-output loopback feed separate 48 kHz AAC tracks through bounded
  timestamped queues and drift-correcting resampling. Source loss inserts silence while retrying;
  native system-output recording and editor output are covered by the short Windows browser
  integration. Microphone-device execution, sustained drift and device changes remain unverified.
  The capture queue retains eight blocks of at most 1024 frames (about 171 ms at 48 kHz).
  Audio pumping shares the interface thread with video encoding. Device-open/pump failures are
  caught for recovery without a visible source-health indication, so a selected sound source can
  silently contribute silence. `Recorder.advance` also returns before pumping audio when an
  attached window is hidden; video pause/resume are no-ops. This case has no native regression.
  The existing resampler stress checks isolate four-hour clock arithmetic and synthetic drift;
  the browser's constant tone proves sound presence, not long-term audiovisual alignment.
- Next: keep audio capture/draining active independently of window visibility and video work,
  report unavailable/lost sources and expose a compact signal/health reading beside the capture.
  Verify a microphone and system sound together, endpoint changes and unplug/replug on Windows.
  Use synchronized visual flashes and sound markers in the two-hour runner from app.capture.011
  to measure alignment throughout recording and after seek/export, including the first and last
  audible samples. Correct drift against the common session clock rather than hiding it in playback.
- Done when: a two-hour native recording keeps each available sound source within one video frame
  of its visual markers, with bounded queues and reported source loss. Hiding/restoring the target
  and changing an audio device preserve the usable recording and its timeline. Retain four-hour
  drift coverage in std.audio.016. Sound-only capture and post-recording track controls are separate
  product work and do not gate reliable video recording.
- Related: std.audio.011, std.audio.013, std.audio.015, std.audio.016, app.capture.011,
  app.capture.038

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

### app.capture.037 — Make export conversion explicit and cancellable

- Evidence: compatible native H.264 trims now preserve compressed interiors and AAC packets,
  encoding only the dependent head and timed annotation spans through their next original IDR.
  The maintained two-hour fixture exercises that path through the native editor. Geometry changes,
  incompatible imported AVC and non-frame-aligned cuts still fall back to full H.264/AAC conversion
  synchronously. The app does not explain that slower path or expose cancellation, output quality,
  encoder or cadence choices. Codec/FPS conversion choices are not implemented. FFmpeg decodes
  every retained picture but exposes final AAC padding ignored by the native reader.
- Next: expose a small export choice that distinguishes preserving the source from conversion,
  with progress and cancellation for slow work. Keep the recording and existing destination intact
  on cancellation. Offer only supported encoder/quality/cadence combinations and retain the source
  cadence by default. Resolve the final AAC-padding interoperability in std.video.016 before
  promising sample-exact external playback. Add realistic large-payload fixture measurements and
  memory observations; the compact two-hour fixture proves timestamp/packet scale, not 1080p I/O.
- Done when: a user can predict whether an export copies or converts, stop a slow export safely,
  and choose supported conversion settings without turning the capture editor into a montage tool.
- Related: app.capture.011, app.capture.014, std.video.016, std.video.017, std.audio.015

### app.capture.016 — No reusable capture layout templates

- Next: persist named layout descriptions produced by app.capture.015 and apply them to a new
  selection of captures.
- Done when: a saved template survives restart and reproduces its ordering, spacing and bounds.
- Related: app.capture.015

### app.capture.017 — Stamp library

- Next: design a reusable stamp set following `design-swag-identity` and place stamps as
  `FormImage` instances.
- Done when: stamps can be browsed and placed from the editor and remain editable images.
