# Findings — sFileScope

The sFileScope application under `bin/apps/modules/sFileScope`. Intent for the same application is
[todo.filescope.md](todo.filescope.md). Leads it merely exposes stay with the module that will fix
them.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

### F-156 — sFileScope sizes its viewer layout in physical pixels, so every viewer overflows at non-100% DPI

- Area: apps/sFileScope
- Found while: migrating the PDF engine into `std/gui` and verifying the new `PdfView` inside the
  running sFileScope on a 150% monitor.
- Observation: sFileScope hands each integrated viewer a content window sized straight from the
  surface's physical pixel size, while gui lays out and paints in logical units times
  `deviceScale`. At 150% the viewer content area measured 1161x730 logical units inside a window
  whose client is only about 978x598 logical, so the viewer — any viewer, this predates the PDF
  rework — is 1.5x wider and taller than the window: a fitted page centres itself in the
  oversized widget and shows up right-shifted and cut. At 100% DPI physical equals logical and
  nothing is visible, which is how it went unnoticed.
- Evidence: an instrumented `PdfView.onPaint` on both monitors of a 150% setup reported
  `position=0,0,1161x730, deviceScale=1.5, fitted zoom=0.867, content centred at x=322` — the
  widget math is exact, the size it was given is not. The sidebar and toolbar paint at their
  layout size times 1.5, matching the screenshots.
- Next step: find where sFileScope computes the content and command areas from the
  surface size and divide by `deviceScale` there; then check the same path in every host that
  sizes children from a `Surface` rectangle, since the surface contract is physical pixels.
  Verify with the HTML viewer at 150%, which should show the same overflow today.

### F-188 — Audio-to-video synchronisation has never been observed against a real output device

- Area: apps/sFileScope
- Found while: T-504, after the video viewer started presenting against the audio clock.
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
- Next step: play a video with sound on a machine whose output is audible and log
  `playbackSampleFrame` against the wall clock for a minute. What has to be true is that it tracks
  real time, that `followAudioClock` corrects a deliberately skewed video clock back onto it, and
  that the correction is not so frequent that it makes the picture stutter — the 0.1 s dead band in
  `VideoAudioDriftSeconds` is a guess until then.
