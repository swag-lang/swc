# Swag Scope Audio Viewer Backlog

The Sound viewer already opens supported audio on a worker, streams playback through `std/audio`,
builds a bounded 4,096-column waveform, seeks, stops, mutes, and controls volume. This backlog owns
the professional listening and inspection surface; decoder and output-engine work remains in
[std.audio.md](std.audio.md).

## Transport and navigation

### app.scope.audio.001 — Audio playback has no speed or pitch policy

- Evidence: transport plays at source speed only. There is no 0.25x–4x rate selector, fine rate
  adjustment, pitch-preserving mode, pitch shift, or visible statement of resampling quality.
- Next: add variable-rate playback first with an explicit pitch-follows-speed mode, then evaluate a
  bounded time-stretch path for speech and music.
- Complete when: speed is visible and keyboard adjustable, seeks and elapsed time remain source-time
  based, A/V-independent sound playback stays stable at supported rates, and unsupported pitch
  preservation is never implied.

### app.scope.audio.002 — Audio cannot loop a selection or mark an A/B region

- Evidence: the timeline supports one playhead and fixed ten-second seeks. There is no range
  selection, set/clear A and B, loop toggle, play-selection, or sample-accurate region readout.
- Next: add a source-frame-backed selection model to the waveform and transport.
- Complete when: pointer and keyboard set a range, loop and play-once honor exact supported frame
  boundaries, start/end/duration are editable in time or frames, and selection survives zoom but
  not an incompatible file replacement.

### app.scope.audio.003 — The waveform cannot zoom, pan, or navigate precisely

- Evidence: one 4,096-sample envelope always represents the entire file. Dense transients and long
  recordings cannot be examined below that aggregate, and the timeline has no navigator, sample
  address, or high-resolution redraw.
- Next: build multiresolution min/max/RMS waveform tiles with a bounded cache and visible-range
  prioritization.
- Complete when: zoom reaches individual samples where the decoder permits, pan and overview stay
  synchronized, numeric time/frame jumps work, waveform detail refines asynchronously, and memory
  is independent of recording duration.

### app.scope.audio.004 — Audio has no markers, chapters, cue-sheet, or navigation history

- Evidence: embedded chapter/cue metadata and sidecar `.cue` files are not presented; a listener
  cannot create temporary landmarks or return through seeks and search-like jumps.
- Next: normalize embedded chapters, cue points, and sidecars into a read-only landmark track, then
  add session bookmarks and back/forward.
- Complete when: landmarks show labels and times, previous/next and filtered list navigation work,
  temporary bookmarks can be exported without modifying media, and invalid cue timing warns.

## Signal inspection

### app.scope.audio.005 — Audio channels cannot be isolated, mixed, or compared

- Evidence: details report channel count, but the waveform and playback present one fixed mix. There
  is no per-channel waveform, mute/solo, stereo L/R/M/S view, phase inversion, downmix policy, or
  channel layout map.
- Next: preserve per-channel waveform aggregates and add a diagnostic channel mixer that feeds only
  the viewer voice.
- Complete when: named channels have separate colors/lanes, mute/solo and common L/R/M/S views are
  available, the active downmix matrix is inspectable, clipping from mixing is reported, and reset
  restores source layout.

### app.scope.audio.006 — Audio has no spectrogram or frequency probe

- Evidence: the only signal view is a time-domain peak/body waveform. Pitch, noise bands, codec
  cutoffs, harmonics, and transient frequency content cannot be inspected.
- Next: add cancellable multiresolution STFT tiles for the visible range with documented window,
  overlap, FFT size, scale, and magnitude units.
- Complete when: linear/log frequency and amplitude scales are selectable, time/frequency probes
  report exact coordinates, settings and color map are visible, zoom refines tiles, and processing
  remains bounded and cancellable.

### app.scope.audio.007 — Audio has no loudness, peak, clipping, silence, or DC analysis

- Evidence: the waveform is visual only. It reports neither sample/true peak nor RMS/LUFS, channel
  balance, clipping runs, silence ranges, DC offset, crest factor, or analysis scope.
- Next: implement cancellable exact peak/RMS/DC and clipping scans, then add a standards-based
  integrated/short-term loudness pass where channel layout is known.
- Complete when: units and thresholds are explicit, whole-file versus selection scope is visible,
  findings navigate to waveform ranges, sample peak is distinguished from true peak, and results
  include decoder/conversion provenance.

### app.scope.audio.008 — Tags, artwork, codec/container facts, and ReplayGain are hidden

- Evidence: the summary carries sample rate, channels, storage bits, and duration only. Title,
  artist, album, date, track/disc, comments, embedded art, codec profile/bitrate, container, delay,
  padding, ReplayGain/R128, and custom tags are not inspectable.
- Next: define an audio metadata model separate from decoded samples and surface it through app.scope.viewers.006.
- Complete when: original tag keys/values and normalized common fields coexist, artwork is bounded
  and opens in Image, technical stream facts include provenance, suspicious or malformed metadata
  warns, and no tag is rewritten.
- Related: app.scope.viewers.006

### app.scope.audio.009 — Lossy codec delay and gapless playback cannot be verified

- Evidence: elapsed time starts at decoded frame zero, but encoder delay, padding, priming, source
  duration, decoded duration, and container edit lists are not shown. Adjacent sibling tracks cannot
  be auditioned gaplessly.
- Next: expose timing provenance from container and codec, then add an optional gapless transition
  between compatible adjacent files.
- Complete when: delay/padding are visible and excluded according to declared policy, duration
  disagreements warn, gapless albums transition without duplicate/missing samples, and seek uses the
  same logical timeline.

## Output and interchange

### app.scope.audio.010 — Output device, format conversion, and device loss are invisible

- Evidence: the viewer acquires the default engine or disables playback. It cannot select a device,
  show negotiated sample format/latency, follow default-device changes, or recover from removal;
  the engine gaps are already std.audio.004, std.audio.005, and std.audio.006.
- Next: design the viewer selector/status around those engine APIs and retain waveform-only
  inspection when output is unavailable.
- Complete when: available outputs and active format/latency are shown, a selected or default device
  can be changed, loss has an actionable state and recovery, and analysis never depends on output.
- Related: std.audio.004, std.audio.005, std.audio.006

### app.scope.audio.011 — Audio selections cannot be copied or exported with exact provenance

- Evidence: there is no Copy Samples, Save Selection, raw-packet extraction, or waveform/spectrogram
  image export. A viewer user cannot carry a suspicious interval into another tool.
- Next: stream the selected decoded frames to a lossless WAV export and copy a bounded sample table,
  then add raw extraction only where container packet boundaries are known.
- Complete when: output states source range, sample rate, channel map, sample format, conversions,
  and decoder; selection export is cancellable; clipping is never introduced silently; and source
  media remains unchanged.
