# Audio Roadmap

This file is the roadmap for `std/audio`, measured against the embeddable audio libraries it
competes with: miniaudio, SoLoud, OpenAL Soft, and the commercial tier of FMOD and Wwise.

It is not the repository's discovery backlog. Cross-cutting leads and defects belong in the
`findings.*` files, which hold evidence; compiler and language intent belongs in
[todo.compiler.md](todo.compiler.md) and [todo.language.md](todo.language.md). This file holds
intent about `bin/std/modules/audio`. [README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

A process-wide engine with an explicit lifecycle, a bus tree with parent routing and per-bus gain,
voices with linear and decibel gain, pitch through a frequency ratio, looping, fire-and-forget
lifetime, and streaming through three rotating 64 KiB decoded buffers. A codec registry
(`ICodec`, `registerCodec`) that makes decoding extensible from outside the module. A no-sound
driver that preserves the entire lifecycle without opening a device, wired into the sandbox so a
test run never makes noise — that last part is better integrated than in most libraries of this
size.

The shape is sound. What is missing is breadth: one container, one platform, no spatialization, no
effects, no capture.

---

## Tier A — What blocks real use

### T-058 — No MP3 decoder

- Problem: `SoundFile.load` accepts WAV alone, and `src/file/wav.swg` accepts only `WAVE_FORMAT_PCM`
  (8, 16, 24 and 32 bit), `WAVE_FORMAT_IEEE_FLOAT`, and `WAVE_FORMAT_EXTENSIBLE` wrapping those two.
  `WAVE_FORMAT_ADPCM` is declared as a constant and then rejected. One codec is registered:
  `CodecPcmToPcm16`.
- Consequence: no music. A three-minute track as 16-bit stereo WAV is about 30 MiB, so any
  application with a soundtrack is pushed off this module immediately. miniaudio ships WAV, FLAC
  and MP3 in the box; SoLoud adds Vorbis.
- Add a clean-room or permissively licensed MP3 decoder behind the existing `ICodec` registry.
  The extension point is already designed and used, so this is decoder work rather than
  architecture work.
- Why first: everything else on this list is a refinement of a library that plays audio. This is
  what decides whether it can be used at all.
- Related: T-166, T-167, T-168, T-169, T-060

### T-166 — No Ogg Vorbis decoder

Add Ogg framing and Vorbis decoding behind `ICodec`, including streaming and seek-table behavior.

- Related: T-058, T-060

### T-167 — No FLAC decoder

Add native FLAC decoding with streaming, metadata bounds, and exact PCM output tests.

- Related: T-058, T-060

### T-168 — No Opus decoder

Add Ogg Opus decoding only as its own optional codec; do not make it part of MP3, Vorbis, or FLAC
completion.

- Related: T-166

### T-169 — WAV ADPCM is declared but rejected

Implement the declared `WAVE_FORMAT_ADPCM` path independently of adding compressed music
containers.

- Related: T-058

### T-059 — Volume changes are instantaneous, so they click

- Problem: `Voice.setVolumeDb` and `Bus.setVolume` write the gain straight to the backend. XAudio2
  applies it at the next processing pass without smoothing, so any gain change during playback is a
  discontinuity in the waveform — an audible click. There is no fade-in, no fade-out, and no ramp.
- Consequence: stopping a sound cleanly is impossible. Every practical use — ducking music under a
  voice line, fading a loop out, starting a sound without a transient — needs a ramp.
- Fix: a ramp duration on the gain setters, and explicit `fadeIn`/`fadeOut` on `Voice` and `Bus`,
  interpolated over a frame count rather than applied at once.
- Cost: low. This is the highest value-to-effort entry in the module.

### T-060 — No seek

- Problem: `Voice.rewindData` restarts a source at the beginning. There is no way to start playback
  at an offset, or to move the play position of a running voice.
- Consequence: no scrubbing, no resume, no jumping within a track, no sample-accurate loop points.
- Fix: a seek on the codec interface with a byte-offset fallback for the constant-bitrate PCM case,
  plus a public `Voice.seek` in seconds or frames.
- Note: this must be designed alongside T-058. Seeking in MP3 and Vorbis is not a byte offset,
  so the codec interface needs the right shape before three decoders are written against the
  wrong one.

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

## Tier B — Capability already half-present

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

## Tier C — Breadth

### T-064 — Engine creation cost on the startup path

- `DriverNative.createNative` does COM initialization, `XAudio2Create`, mastering-voice creation,
  channel-mask query and `X3DAudioInitialize`. Engine creation was previously measured in the 500
  to 950 millisecond range, which dominates the startup of the example scripts that call it —
  `bin/examples/scripts/flappy.swgs`, `invaders.swgs` and `pacman.swgs`.
- Re-measure before acting; then consider deferring device work off the calling thread so the
  application can draw its first frame while the engine comes up.
- Related: no `findings.*` file has an entry for this. If measurement shows the cost is in XAudio2
  rather than in this module, record it there instead.

### T-065 — No audio capture input

- Add capture-device enumeration and a recording stream as a peer of playback.
- This is what a recorder, a voice-chat path, or a level meter would need. It is also a prerequisite
  if `sCapture` ever records video with sound —
  [T-081](todo.scapture.md#t-081--video-and-animated-gif-recording).
- Related: T-175, T-176, T-245

### T-175 — No full-duplex audio session

Allow synchronized input and output in one engine session for voice communication and live
processing.

- Related: T-065

### T-176 — No system-output loopback capture

Expose desktop/output loopback as a distinct capture source when the backend supports it.

- Related: T-065, T-245

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

**Bundled codec licensing.** Any format added under T-058 must be a clean-room or
permissively-licensed implementation. Do not vendor a decoder whose terms cannot be satisfied by a
standard library shipped with a compiler.
