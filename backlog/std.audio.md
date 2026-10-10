# Audio Backlog

This backlog covers `std/audio`, measured against the embeddable audio libraries it
competes with: miniaudio, SoLoud, OpenAL Soft, and the commercial tier of FMOD and Wwise.

Cross-cutting compiler and language work belongs in [compiler.core.md](compiler.core.md) and
[language.design.md](language.design.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/audio` together. [README.md](README.md) has the whole layout.


## Entries

### std.audio.010 — Engine creation cost on the startup path

- `XAudio2DriverNative.createXAudio2` does COM initialization, `XAudio2Create`, mastering-voice creation,
  channel-mask query and `X3DAudioInitialize`. Engine creation was previously measured in the 500
  to 950 millisecond range, which dominates the startup of the example scripts that call it —
  `bin/examples/scripts/flappy.swgs`, `invaders.swgs` and `pacman.swgs`.
- Re-measure before acting; then consider deferring device work off the calling thread so the
  application can draw its first frame while the engine comes up.
- Related: platform.portability.063 (the X3DAudio initialization it pays for is never used),
  platform.portability.065; moving bring-up off the calling thread is backend-neutral.

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

- Problem: `Voice.setVolumeDb` and `Bus.setVolume` write the gain straight to the backend. XAudio2
  applies a target gain without a ramp owned by this module. An abrupt change on a nonzero sample
  can produce a discontinuity; this is a risk, not evidence that every gain change audibly clicks.
  There is no fade-in, fade-out, or sample-based interpolation contract.
- Consequence: a caller cannot request a timed fade or ducking envelope through the audio API.
- Fix: a ramp duration on the gain setters, and explicit `fadeIn`/`fadeOut` on `Voice` and `Bus`,
  interpolated over a frame count rather than applied at once.
- Next: define the ramp's interaction with batches, pause, seek, and bus routing, then verify its
  samples with the no-sound backend before judging playback on a device.

### std.audio.004 — No output-device enumeration

- Enumerate output devices with stable session identifiers and enough capabilities for a caller to
  present a choice.
- Related: std.audio.005, std.audio.006

### std.audio.005 — The engine cannot select an output device


Allow `createEngine` or a dedicated switch operation to target one identifier returned by std.audio.004,
with a defined fallback when that device is unavailable.

- Related: std.audio.004, std.audio.006

### std.audio.006 — Output-device loss is not reported or recovered


Handle the backend's critical-error signal, report the loss, and rebuild or fail over according to
an explicit policy when headphones, USB audio, or the default device changes.

- Related: std.audio.004, std.audio.005

### std.audio.007 — No stereo pan control


Add backend-neutral stereo panning to `Voice` without requiring the listener and distance model of
platform.portability.063.

- Related: platform.portability.063

### std.audio.008 — No reverb effect


Expose a reverb effect independently of the basic voice filters and of a general effects graph.

- Related: platform.portability.064, std.audio.014

### std.audio.009 — No echo effect


Expose an echo/delay effect independently of reverb and the general effects graph.

- Related: platform.portability.064, std.audio.014

### std.audio.011 — No audio capture input

- Add capture-device enumeration and a recording stream as a peer of playback.
- This is what a recorder, a voice-chat path, or a level meter would need. It is also a prerequisite
  if `Swag Capture` ever records video with sound —
  [app.capture.011](app.capture.md#appcapture011--no-video-recording).
- Related: std.audio.012, std.audio.013, app.capture.013

### std.audio.012 — No full-duplex audio session


Allow synchronized input and output in one engine session for voice communication and live
processing.

- Related: std.audio.011

### std.audio.013 — No system-output loopback capture


Expose desktop/output loopback as a distinct capture source when the backend supports it.

- Related: std.audio.011, app.capture.013

### std.audio.014 — Effects graph

- Buses route and scale gain. They do not process. FMOD, Wwise, SoLoud and miniaudio all expose a
  DSP or node graph where an effect can be inserted on a bus.
- Sequence this after platform.portability.064: a per-voice filter answers most of the need, and an effects graph is
  a much larger commitment. Do not build the graph to get the filter.
- Related: platform.portability.064, std.audio.008, std.audio.009

---
