# `std/screen`

The `screen` module owns live desktop acquisition. It delivers reusable frames to callers;
Swag Capture owns area selection, recording pace, cursor policy, encoding, and the capture document.
The first consumer is video recording, but a still picture can use the same source. `std/video`
continues to own media frames and codecs, not desktop access.

### std.screen.001 — Define one live-screen source contract

- Evidence: `Screen.Source` now owns native resources and writes reusable bottom-up BGRA8 for a
  physical desktop area. `SourceMetrics` separates acquisition, readback, copying and composition;
  native Windows and X11 tests exercise opening, capture and recovery. The API reports unchanged
  pixels and can leave the caller's target untouched when `copyUnchanged` is false, avoiding a
  cached-frame copy for a recorder that will emit a held picture. It does not yet publish source
  presentation time or a borrowed GPU frame.
- Next: add source presentation timestamps and a bounded borrowed-frame contract, monitor/window
  targets, permission and source-loss results, and frame-age diagnostics. Keep pacing and encoding
  outside the source.
- Done when: callers can distinguish stale pixels, source age, readback delay and loss while
  retaining a frame safely across a consumer handoff on Windows and Linux.
- Related: std.screen.002, std.screen.003, app.capture.011

### std.screen.002 — Acquire Windows monitor and window frames without GDI polling

- Evidence: a 2304x1296 `BitBlt` read took about 33 ms and a 5120x1440 desktop read about 50 ms
  in a native probe; direct scaling and parallel GDI reads did not remove the cost. At 30 fps,
  the latter exceeds the entire frame interval before encoding starts. A standalone DXGI probe
  acquired 120 successive frames on each 3840x2160 output while a small window changed: GPU
  copy plus CPU mapping averaged 7.4 and 11.0 ms, followed by about 4.4 ms to copy rows. The
  GDI and DXGI probes used different DPI contexts, and this short sample does not measure crop,
  compositing, encoding or sustained load. Native 2304x1296 browser recordings varied from zero
  to 83 missed slots out of about 179, tracking `BitBlt` cost rather than interface stalls.
  Direct3D 11/DXGI Desktop Duplication now reads single and adjacent monitors into
  Swag Capture video, with a GDI fallback. A 2304x1296 browser recording with cursor and system
  sound decoded 179 frames and missed 11 slots in one six-second run; another missed two. A
  3840x2160 monitor recording missed six slots in three seconds. The 7680x2169 virtual desktop,
  reduced to 4096x1156 for H.264, missed five to 29 slots in three-second runs after direct
  multi-output composition. DXGI dirty and moved rectangles now limit GPU readback and CPU row
  copies to changed bounds when the selection covers at least three quarters of an output. A
  three-second virtual-desktop run used 166 partial reads and copied 68.7 million pixels, missing
  five slots while decoding all 86 output frames. A single 3840x2160 monitor run used 57 partial
  reads, copied 140.8 million pixels and missed one of 90 slots. On this device, partially
  updating the staging texture for a 1920x1080 crop increased readback time, so smaller selections
  retain a full staging copy; one six-second crop run decoded 179 frames, replayed sound and missed
  one slot. The virtual-desktop source can now mirror only changed regions into the recorder's
  stable capture image, while retaining its own composed cache. A three-second run with 170 DXGI
  frames spent 115 ms in composition and 564 ms in the complete screen grab, decoding 90 output
  frames with five missed slots. An earlier run with a complete composed-image copy spent 911 ms
  in composition alone. The workloads differed, and missed slots varied between runs. These short
  samples and changing desktop content do not establish sustained cadence. The Windows backend now
  writes both single-output and multi-output frames into one owned composed cache. Large
  cache-to-caller copies use parallel blocks: a 7680x2168 byte-for-byte test took 78 ms for 16
  frames versus 200 ms with serial copying on Windows. A Linux run took 140 versus 150 ms for the
  same case. Large pitched DXGI readbacks use parallel row groups, retaining the serial path for
  smaller regions; a synthetic 7680x2168 pitched readback took 68 versus 143 ms for 16 frames,
  with exact output. These are CPU copy measurements, not end-to-end readback timings. The first
  acquired DXGI frame now counts as fresh even when it carries only pointer metadata. A later
  dual-output live A/B/A check found that parallel copying each changed region reduced isolated
  composition time but coincided with longer GPU readback and more missed slots; that change was
  removed. Multi-output acquisition now submits both GPU readbacks before mapping either staging
  texture. Native tests cover abort and final composed pixels; short full-desktop recordings can
  run without missed slots, but sustained cadence remains sensitive to machine load. DXGI now
  reports coalesced desktop updates and maximum acquisition/readback waits separately. A
  30-second moving-fixture full-desktop recording decoded 901 pictures at 4096x1156 with no
  missed slots. A 60-second run decoded 1778 pictures, missed 49 slots, and had one 302 ms
  readback wait with no source failures; short runs can conceal GPU stalls. When at most eight
  DXGI update rectangles cover less than half their union, the backend now queues each rectangle
  separately and maps the staging texture once. A synthetic pitched-image test checks separate
  top-down regions and bottom-up output. In a 30-second on/off/on comparison, pixel copies were
  265/1051/258 million and CPU copy time 150/351/170 ms; all three files decoded and missed no
  slots. Readback time was 2.55/4.05/4.82 s, so that comparison does not establish a GPU wait
  improvement. A separate 60-second run with regional copies decoded 1801 pictures, missed no
  slots and copied 513 million pixels, but desktop load differed from the earlier long run. The
  stable caller image now receives those same rectangles instead of their union. A 30-second
  full-desktop run mirrored 275 million pixels and spent 154 ms in composition, compared with
  roughly 460-513 ms in the preceding runs that mirrored each union; it decoded 901 pictures
  with no missed slots. The exact desktop workload varied between runs. Outputs on the same
  adapter now share one D3D11 device/context and one command flush per capture. Reopening a
  source releases its old duplication first, as DXGI allows only one duplication per output in
  a process; native tests cover successful and failed reopen paths. A shared/separate/shared
  30-second sequence spent 0.67/5.89/0.98 s in readback and missed 0/3/0 slots, but the
  separate run copied roughly four times as many pixels under higher desktop load, so those
  timings do not isolate the device-sharing benefit. A 60-second shared run still had a 319 ms
  readback spike and missed 42 slots; long-tail GPU waits remain open.
- Next: preserve native presentation timestamps and pointer metadata; handle rotation, adapters
  beyond the default adapter and access loss. Add Windows Graphics Capture
  for window targets, including occluded windows. Reduce readback and CPU copying for simultaneous
  outputs after profiling GPU readback stalls, and measure sustained cadence under desktop motion
  and machine load.
- Done when: the native consumer sustains 30 fps on a moving 5120x1440 desktop on a supported
  Windows machine, reports source and readback losses separately, and resumes after display
  changes. A covered window remains capturable through the window source.
- Related: std.screen.001, platform.portability.097, platform.portability.098

### std.screen.003 — Acquire Linux screen frames across X11 and Wayland

- Evidence: X11 acquisition moved behind `Screen.Source` and Swag Capture video uses it.
  Xvfb tests cover native BGRA8 reads, MIT-SHM, broken-socket recovery and seven application
  capture scenarios. A Wayland session cannot read the compositor through the X11 root.
- Next: add ScreenCast portal selection and a PipeWire stream for Wayland monitor/window targets.
  Negotiate the available buffer type,
  starting with shared-memory readback and measuring DMA-BUF where supported. Expose portal
  cancellation and source termination as normal source results.
- Done when: the native consumer records timestamped monitor and window frames on X11 and
  Wayland, survives a resolution change or source closure without a hang, and states the
  measured acquisition and readback cost for each backend.
- Related: std.screen.001, platform.portability.101

### std.screen.004 — Switch Swag Capture to timed screen frames

- Evidence: video uses `Screen.Source` on Windows and Linux/X11; Windows retains GDI for source
  failure and still pictures. The native browser runner verifies 1080p and 2304x1296 recording,
  system sound, editor replay, one-monitor capture and the virtual desktop. The recorder still
  counts requested slots rather than the age of the desktop frame.
- Next: use `Screen.Source` for still pictures, separate source age, readback time, encoder backlog
  and repeated output frames in recording diagnostics, and retain GDI only as a documented
  fallback. Keep audio servicing independent of the screen source.
- Done when: the 1080p and multi-monitor browser recording runners show source and encoder
  losses separately; still pictures, area capture, attached-window recording, cursor policy and
  control exclusion behave as before; and the selected native backend meets its measured
  cadence without growing its queue.
- Related: std.screen.001, std.screen.002, std.screen.003, app.capture.011
