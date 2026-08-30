# Audio Backlog

This backlog covers `std/audio`, measured against the embeddable audio libraries it
competes with: miniaudio, SoLoud, OpenAL Soft, and the commercial tier of FMOD and Wwise.

Cross-cutting compiler and language work belongs in [compiler.md](compiler.md) and
[language.md](language.md). This file keeps the evidence, investigations, and intended outcomes
owned by `bin/std/modules/audio` together. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

A process-wide engine with an explicit lifecycle, a bus tree with parent routing and per-bus gain,
voices with linear and decibel gain, pitch through a frequency ratio, looping, fire-and-forget
lifetime, and streaming through three rotating 64 KiB decoded buffers. A codec registry
(`ICodec`, `registerCodec`) that makes decoding extensible from outside the module, with AAC-LC,
AC-3, independent E-AC-3, DTS Core, FLAC, MPEG Layer III, Vorbis, Opus, and WAVE ADPCM decoders in
the box. DTS, FLAC, MP3, and Ogg also have their own file readers, so a `.dts`, `.flac`, `.mp3`,
`.ogg`, or `.opus` opens through `SoundFile.load` and streams from
disk; that is the answer to "no music", and what is left below is breadth beside it. A no-sound
driver that preserves the entire lifecycle without opening a device, wired into the sandbox so a
test run never makes noise — that last part is better integrated than in most libraries of this
size.

The shape is sound. What is missing is breadth: one container, one platform, no spatialization, no
effects, no capture.

---

## Tier A — Compressed audio formats

### B-011 — DTS Core advanced coding tools remain unsupported

- Evidence: the decoder accepts scalar-coded 14- and 16-bit Core streams, reconstructs four-tap
  ADPCM prediction across frame boundaries, and consumes VQ-bearing frames while omitting those
  high-frequency bands. It still explicitly rejects Huffman-coded side information or audio,
  joint intensity, and extension substreams. Prediction and VQ omission are validated against
  DTS-HD Core packets from a real-world Matroska stream; the reproducible `dcaenc` fixture
  exercises none of the remaining tools.
- Next: obtain a permissively redistributable stream that exercises the common Core tool set, or
  a reproducible encoder for one, then implement and validate each tool against that corpus.
- Complete when: representative Core streams using those tools decode with validated channel order
  and bounded reference error, while unsupported extension substreams remain explicit.

### B-563 — MP3 costs more per frame than it needs to, and ISO-BMFF does not carry it

- Intent: Layer III decodes correctly at every sampling frequency of the three versions, within
  2.3e-5 of full scale of FFmpeg. Nothing about its speed has been measured, and its ISO-BMFF
  carriage is not read; Matroska carriage is complete.
- What is slow by construction, and was written that way on purpose: the inverse transform is the
  normative matrix, 648 multiplications a subband where a factored transform needs a fraction of
  that, and the polyphase bank is the normative 64 by 32 matrixing per block. Both are stated in
  `synthesis.swg` exactly as clause 2.4.3.4.10 states them, which is what made them checkable.
  `Math.pow` also computes every magnitude above fifteen. Measure before replacing any of it: at
  128 kbit/s a frame is 26 ms of audio and the whole decode may already be far below that.
- What is not carried: an ISO-BMFF `mp4a` entry whose object type is 0x69 or 0x6B is Layer III,
  and `mp4.swg` rejects every object type but AAC's 0x40.
## Tier A — Playback control

### B-213 — Volume changes are instantaneous, so they click

- Problem: `Voice.setVolumeDb` and `Bus.setVolume` write the gain straight to the backend. XAudio2
  applies it at the next processing pass without smoothing, so any gain change during playback is a
  discontinuity in the waveform — an audible click. There is no fade-in, no fade-out, and no ramp.
- Consequence: stopping a sound cleanly is impossible. Every practical use — ducking music under a
  voice line, fading a loop out, starting a sound without a transient — needs a ramp.
- Fix: a ramp duration on the gain setters, and explicit `fadeIn`/`fadeOut` on `Voice` and `Bus`,
  interpolated over a frame count rather than applied at once.
- Cost: low. This is the highest value-to-effort entry in the module.

## Tier A — Output-device lifecycle

### B-214 — No output-device enumeration

- Enumerate output devices with stable session identifiers and enough capabilities for a caller to
  present a choice.
- Related: B-292, B-293

### B-292 — The engine cannot select an output device

Allow `createEngine` or a dedicated switch operation to target one identifier returned by B-214,
with a defined fallback when that device is unavailable.

- Related: B-214, B-293

### B-293 — Output-device loss is not reported or recovered

Handle the backend's critical-error signal, report the loss, and rebuild or fail over according to
an explicit policy when headphones, USB audio, or the default device changes.

- Related: B-214, B-292

---

## Tier B — Spatialization and channel control

Two features are already paid for in the backend and simply not exposed. They are cheap in a way
the rest of this list is not.


### B-294 — No stereo pan control

Add backend-neutral stereo panning to `Voice` without requiring the listener and distance model of
B-215.

- Related: B-215

## Tier B — Voice effects


### B-295 — No reverb effect

Expose a reverb effect independently of the basic voice filters and of a general effects graph.

- Related: B-216, B-220

### B-296 — No echo effect

Expose an echo/delay effect independently of reverb and the general effects graph.

- Related: B-216, B-220

---

## Tier C — Startup and capture workflows

### B-217 — Engine creation cost on the startup path

- `DriverNative.createNative` does COM initialization, `XAudio2Create`, mastering-voice creation,
  channel-mask query and `X3DAudioInitialize`. Engine creation was previously measured in the 500
  to 950 millisecond range, which dominates the startup of the example scripts that call it —
  `bin/examples/scripts/flappy.swgs`, `invaders.swgs` and `pacman.swgs`.
- Re-measure before acting; then consider deferring device work off the calling thread so the
  application can draw its first frame while the engine comes up.
- Related: no other backlog entry covers this. If measurement shows the cost is in XAudio2
  rather than in this module, record it there instead.

### B-218 — No audio capture input

- Add capture-device enumeration and a recording stream as a peer of playback.
- This is what a recorder, a voice-chat path, or a level meter would need. It is also a prerequisite
  if `Swag Capture` ever records video with sound —
  [B-231](capture.md#b-231--no-video-recording).
- Related: B-297, B-298, B-353

### B-297 — No full-duplex audio session

Allow synchronized input and output in one engine session for voice communication and live
processing.

- Related: B-218

### B-298 — No system-output loopback capture

Expose desktop/output loopback as a distinct capture source when the backend supports it.

- Related: B-218, B-353

## Tier C — Backend and graph architecture


### B-220 — Effects graph

- Buses route and scale gain. They do not process. FMOD, Wwise, SoLoud and miniaudio all expose a
  DSP or node graph where an effect can be inserted on a bus.
- Sequence this after B-216: a per-voice filter answers most of the need, and an effects graph is
  a much larger commitment. Do not build the graph to get the filter.

---

## Out of scope

**An authoring tool.** FMOD Studio and Wwise are as much authoring applications as they are
runtimes — banks, events, parameters, adaptive music, and a designer-facing editor. That is a
product, not a standard-library module.

**Bundled codec licensing.** Every format added here must be a clean-room or permissively-licensed
implementation. Do not vendor a decoder whose terms cannot be satisfied by a standard library
shipped with a compiler. Normative tables are a separate question from code: Layer III's were
recovered from two public-domain implementations and checked against each other, with the
provenance in `bin/THIRDPARTY.md`; a table is a fact of the format, a decoder is expression.
