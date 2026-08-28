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
AC-3, independent E-AC-3, DTS Core, FLAC and MPEG Layer III decoders in the box. DTS, FLAC and MP3 also have
their own file readers, so a `.dts`, `.flac`, or `.mp3` opens through `SoundFile.load` and streams from
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

### T-166 — No Ogg Vorbis decoder

Add Ogg framing and Vorbis decoding behind `ICodec`, including streaming and seek-table behavior.
Vorbis transmits its codebooks in the stream, so unlike Layer III it needs no normative code table
to be recovered from anywhere, which makes it the cheapest remaining format to be certain about.

- What the packet index has to do differently, worked out and not yet built: a Vorbis packet may
  span Ogg pages, so it is not one contiguous byte range and `SoundPacket` cannot name it. Index
  whole pages instead, merging consecutive pages until the granule position advances, and let the
  codec assemble packets across the boundary in its own state. The granule delta of the merged run
  is exactly the sample-frame count the entry owes, which is what `Voice.decodePacketData`
  demands; no mode simulation is needed to compute it.
- How much it is worth, measured (2026-08-25, 592 films of one personal library): 2 Vorbis tracks.
  It is the right next audio format for correctness reasons, not for reach.

### T-168 — No Opus decoder

Add Ogg Opus decoding only as its own optional codec; do not make it part of Vorbis or FLAC
completion.

- Related: T-166

### T-169 — WAV ADPCM is declared but rejected

Implement the declared `WAVE_FORMAT_ADPCM` path independently of adding compressed music
containers.

### T-564 — MP3 costs more per frame than it needs to, and ISO-BMFF does not carry it

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

### T-059 — Volume changes are instantaneous, so they click

- Problem: `Voice.setVolumeDb` and `Bus.setVolume` write the gain straight to the backend. XAudio2
  applies it at the next processing pass without smoothing, so any gain change during playback is a
  discontinuity in the waveform — an audible click. There is no fade-in, no fade-out, and no ramp.
- Consequence: stopping a sound cleanly is impossible. Every practical use — ducking music under a
  voice line, fading a loop out, starting a sound without a transient — needs a ramp.
- Fix: a ramp duration on the gain setters, and explicit `fadeIn`/`fadeOut` on `Voice` and `Bus`,
  interpolated over a frame count rather than applied at once.
- Cost: low. This is the highest value-to-effort entry in the module.

## Tier A — Output-device lifecycle

### T-061 — No output-device enumeration

- Enumerate output devices with stable session identifiers and enough capabilities for a caller to
  present a choice.
- Related: T-170, T-171

### T-170 — The engine cannot select an output device

Allow `createEngine` or a dedicated switch operation to target one identifier returned by T-061,
with a defined fallback when that device is unavailable.

- Related: T-061, T-171

### T-171 — Output-device loss is not reported or recovered

Handle the backend's critical-error signal, report the loss, and rebuild or fail over according to
an explicit policy when headphones, USB audio, or the default device changes.

- Related: T-061, T-170

---

## Tier B — Spatialization and channel control

Two features are already paid for in the backend and simply not exposed. They are cheap in a way
the rest of this list is not.

### T-062 — Spatialization, with X3DAudio already initialized

- `src/driver/xaudio2.swg` calls `X3DAudioInitialize` and stores the handle in `x3DInstance`. That
  handle is never read again. The 3D engine is initialized on every engine creation and does
  nothing.
- Missing above it: a listener, a per-voice position, distance attenuation, and a matrix apply on
  the source voice. X3DAudio computes the output matrix; the module has to feed it and apply the
  result.
- Related: T-172

### T-172 — No stereo pan control

Add backend-neutral stereo panning to `Voice` without requiring the listener and distance model of
T-062.

- Related: T-062

## Tier B — Voice effects

### T-063 — Filters, with the voice flag already set

- Submix voices are created with `XAUDIO2_VOICE_USEFILTER` in `src/driver/xaudio2.swg`. The
  capability is requested and no API exposes it.
- XAudio2 gives a per-voice low-pass, high-pass, band-pass and notch filter once that flag is set.
- A cutoff and resonance on `Voice` and `Bus` is a small surface over a capability that is already
  being paid for on every submix.
- Related: T-173, T-174, T-067

### T-173 — No reverb effect

Expose a reverb effect independently of the basic voice filters and of a general effects graph.

- Related: T-063, T-067

### T-174 — No echo effect

Expose an echo/delay effect independently of reverb and the general effects graph.

- Related: T-063, T-067

---

## Tier C — Startup and capture workflows

### T-064 — Engine creation cost on the startup path

- `DriverNative.createNative` does COM initialization, `XAudio2Create`, mastering-voice creation,
  channel-mask query and `X3DAudioInitialize`. Engine creation was previously measured in the 500
  to 950 millisecond range, which dominates the startup of the example scripts that call it —
  `bin/examples/scripts/flappy.swgs`, `invaders.swgs` and `pacman.swgs`.
- Re-measure before acting; then consider deferring device work off the calling thread so the
  application can draw its first frame while the engine comes up.
- Related: no other backlog entry covers this. If measurement shows the cost is in XAudio2
  rather than in this module, record it there instead.

### T-065 — No audio capture input

- Add capture-device enumeration and a recording stream as a peer of playback.
- This is what a recorder, a voice-chat path, or a level meter would need. It is also a prerequisite
  if `sSnapForge` ever records video with sound —
  [T-081](snapforge.md#t-081--no-video-recording).
- Related: T-175, T-176, T-245

### T-175 — No full-duplex audio session

Allow synchronized input and output in one engine session for voice communication and live
processing.

- Related: T-065

### T-176 — No system-output loopback capture

Expose desktop/output loopback as a distinct capture source when the backend supports it.

- Related: T-065, T-245

## Tier C — Backend and graph architecture

### T-066 — A second platform

- `DriverKind` is `Default`, `NoSound`, `XAudio2`. Off Windows, `Default` resolves to silence.
- The backend boundary in `src/driver/backend.swg` is clean and already has two implementations, so
  a third is additive rather than structural. CoreAudio and ALSA or PulseAudio are the obvious
  targets; WASAPI directly would also remove the XAudio2 dependency on Windows.

### T-067 — Effects graph

- Buses route and scale gain. They do not process. FMOD, Wwise, SoLoud and miniaudio all expose a
  DSP or node graph where an effect can be inserted on a bus.
- Sequence this after T-063: a per-voice filter answers most of the need, and an effects graph is
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
