# Audio Backlog

This backlog covers `std/audio`, measured against the embeddable audio libraries it
competes with: miniaudio, SoLoud, OpenAL Soft, and the commercial tier of FMOD and Wwise.

Cross-cutting compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/audio` together. [README.md](README.md) has the whole layout.


## Entries

### std.audio.010 — Engine creation cost on the startup path

- Evidence: `XAudio2DriverNative.createXAudio2` (`src/driver/xaudio2.swg`) does COM
  initialization, `XAudio2Create`, mastering-voice creation, channel-mask query and
  `X3DAudioInitialize` on the calling thread; it dominates the startup of
  `bin/examples/scripts/flappy.swgs`, `invaders.swgs` and `pacman.swgs`. The X3DAudio
  initialization it pays for is never used (platform.portability.063).
- Next: measure engine creation in one of those scripts, then move device bring-up off the
  calling thread so the first frame can draw while the engine comes up; this is backend-neutral.
- Done when: engine creation no longer delays the first frame of those scripts, with the
  measured cost recorded in the commit.
- Related: platform.portability.063, platform.portability.065

### std.audio.001 — DTS Core advanced coding tools remain unsupported

- Evidence: the decoder accepts scalar-coded 14- and 16-bit Core streams, reconstructs four-tap
  ADPCM prediction across frame boundaries, and consumes VQ-bearing frames while omitting those
  high-frequency bands. It still explicitly rejects Huffman-coded side information or audio,
  and joint intensity. DTS-HD packets are accepted through their backward-compatible Core prefix;
  extension substreams are not decoded. Prediction and VQ omission are validated against
  DTS-HD Core packets from a real-world Matroska stream; the reproducible `dcaenc` fixture
  exercises none of the remaining tools.
- Next: obtain a permissively redistributable stream that exercises the common Core tool set, or
  a reproducible encoder for one, then implement and validate each tool against that corpus.
- Done when: representative Core streams using those tools decode with validated channel order
  and bounded reference error, while unsupported extension substreams remain explicit.

### std.audio.002 — MP3 synthesis has not been measured or factored

- Intent: Layer III decodes at every sampling frequency of the three versions, within the
  reference-error limits in `mp3.test.swg`. Its transform and filter-bank cost has not been measured.
- What is slow by construction, and was written that way on purpose: the inverse transform is the
  normative matrix, 648 multiplications a subband where a factored transform needs a fraction of
  that, and the polyphase bank is the normative 64 by 32 matrixing per block. Both are stated in
  `synthesis.swg` exactly as clause 2.4.3.4.10 states them, which is what made them checkable.
  `Math.pow` also computes every magnitude above fifteen. Measure before replacing any of it: at
  128 kbit/s a frame is 26 ms of audio and the whole decode may already be far below that.
- Next: measure synthesis separately from entropy decoding, then compare factored transforms
  against the current reference implementation on the same granules.
- Done when: synthesis cost is recorded and any retained optimization preserves the complete
  MPEG-1/2/2.5, channel-mode, block-type, and reservoir regression corpus.
- Related: std.video.008

### std.audio.003 — Gain changes have no sample-based ramp

- Evidence: `Voice.setVolumeDb` and `Bus.setVolume` write the gain straight to the backend,
  with no ramp owned by this module. A caller cannot request a timed fade or ducking envelope,
  and an abrupt change on a nonzero sample can produce a discontinuity; this is a risk, not
  evidence that every gain change audibly clicks.
- Next: add a ramp duration to the gain setters and `fadeIn`/`fadeOut` on `Voice` and `Bus`,
  defining the ramp's interaction with batches, pause, seek, and bus routing.
- Done when: gain changes interpolate over a requested frame count, verified sample by sample
  with the no-sound backend.

### std.audio.004 — No output-device enumeration

- Next: enumerate output devices with stable session identifiers and enough capabilities for a
  caller to present a choice.
- Done when: The public API enumerates output devices with stable session identifiers and enough
  capability information to present a choice.
- Related: std.audio.005, std.audio.006

### std.audio.005 — The engine cannot select an output device

- Next: allow `createEngine` or a dedicated switch operation to target one identifier returned
  by std.audio.004, with a defined fallback when that device is unavailable.
- Done when: playback can be started on a chosen device, and an unavailable choice follows the
  documented fallback.
- Related: std.audio.004, std.audio.006

### std.audio.006 — Output-device loss is not reported or recovered

- Next: handle the backend's critical-error signal, report the loss, and rebuild or fail over
  according to an explicit policy.
- Done when: unplugging headphones or USB audio, or changing the default device, is reported
  and playback recovers or stops according to that policy.
- Related: std.audio.004, std.audio.005

### std.audio.007 — No stereo pan control

- Next: add backend-neutral stereo panning to `Voice` without requiring the listener and
  distance model of platform.portability.063.
- Done when: `Voice` exposes backend-neutral stereo panning without requiring the listener or
  distance model.
- Related: platform.portability.063

### std.audio.008 — No reverb effect

- Next: expose a reverb effect independently of the basic voice filters and of a general
  effects graph.
- Done when: a voice or bus can enable and parameterize reverb through the public API.
- Related: platform.portability.064, std.audio.014

### std.audio.009 — No echo effect

- Next: expose an echo/delay effect independently of reverb and the general effects graph.
- Done when: a voice or bus can enable and parameterize echo through the public API.
- Related: platform.portability.064, std.audio.014

### std.audio.011 — No audio capture input

- Evidence: a recorder, a voice-chat path, a level meter, and Swag Capture recording with
  sound ([app.capture.011](app.capture.md#appcapture011--no-video-recording)) all need input.
- Next: add capture-device enumeration and a recording stream as a peer of playback.
- Done when: a caller can open a capture device and receive its samples through the public API.
- Related: std.audio.012, std.audio.013, app.capture.013

### std.audio.012 — No full-duplex audio session

- Next: allow synchronized input and output in one engine session.
- Done when: one session captures and plays with a shared clock suitable for voice
  communication and live processing.
- Related: std.audio.011

### std.audio.013 — No system-output loopback capture

- Next: expose desktop/output loopback as a distinct capture source where the backend
  supports it.
- Done when: a caller can record the system output mix, and unsupported backends report it
  explicitly.
- Related: std.audio.011, app.capture.013

### std.audio.014 — Effects graph

- Evidence: buses route and scale gain but do not process; FMOD, Wwise, SoLoud and miniaudio
  all expose a DSP or node graph where an effect can be inserted on a bus.
- Next: sequence this after platform.portability.064: a per-voice filter answers most of the
  need, and an effects graph is a much larger commitment. Do not build the graph to get the
  filter.
- Done when: Effects can be inserted on a bus through a stated DSP or node-graph contract sequenced
  after the per-voice filter boundary.
- Related: platform.portability.064, std.audio.008, std.audio.009

---
