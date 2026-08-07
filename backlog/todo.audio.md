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

### 1. Only WAV, and only some of it

- Problem: `SoundFile.load` accepts WAV alone, and `src/file/wav.swg` accepts only `WAVE_FORMAT_PCM`
  (8, 16, 24 and 32 bit), `WAVE_FORMAT_IEEE_FLOAT`, and `WAVE_FORMAT_EXTENSIBLE` wrapping those two.
  `WAVE_FORMAT_ADPCM` is declared as a constant and then rejected. One codec is registered:
  `CodecPcmToPcm16`.
- Consequence: no music. A three-minute track as 16-bit stereo WAV is about 30 MiB, so any
  application with a soundtrack is pushed off this module immediately. miniaudio ships WAV, FLAC
  and MP3 in the box; SoLoud adds Vorbis.
- Fix: MP3, Ogg Vorbis and FLAC decoders behind the existing `ICodec` registry. The extension point
  is already designed and already used once, so this is decoder work rather than architecture work.
  Opus is a reasonable fourth.
- Why first: everything else on this list is a refinement of a library that plays audio. This is
  what decides whether it can be used at all.

### 2. Volume changes are instantaneous, so they click

- Problem: `Voice.setVolumeDb` and `Bus.setVolume` write the gain straight to the backend. XAudio2
  applies it at the next processing pass without smoothing, so any gain change during playback is a
  discontinuity in the waveform — an audible click. There is no fade-in, no fade-out, and no ramp.
- Consequence: stopping a sound cleanly is impossible. Every practical use — ducking music under a
  voice line, fading a loop out, starting a sound without a transient — needs a ramp.
- Fix: a ramp duration on the gain setters, and explicit `fadeIn`/`fadeOut` on `Voice` and `Bus`,
  interpolated over a frame count rather than applied at once.
- Cost: low. This is the highest value-to-effort entry in the module.

### 3. No seek

- Problem: `Voice.rewindData` restarts a source at the beginning. There is no way to start playback
  at an offset, or to move the play position of a running voice.
- Consequence: no scrubbing, no resume, no jumping within a track, no sample-accurate loop points.
- Fix: a seek on the codec interface with a byte-offset fallback for the constant-bitrate PCM case,
  plus a public `Voice.seek` in seconds or frames.
- Note: this must be designed alongside entry 1. Seeking in MP3 and Vorbis is not a byte offset,
  so the codec interface needs the right shape before three decoders are written against the
  wrong one.

### 4. No device enumeration, selection, or loss handling

- Problem: `createEngine` opens the default device and that is the whole story. There is no way to
  list output devices, no way to choose one, and nothing handles the device disappearing —
  unplugged headphones, a disconnected USB interface, a default-device switch. XAudio2 signals
  this; the module does not listen.
- Consequence: the engine goes silent and stays silent, with no error and no recovery.
- Fix: device enumeration, an explicit device in `createEngine`, and a critical-error callback that
  rebuilds the engine on the new default device.
- Every competing library treats this as baseline, because on a desktop it happens weekly.

---

## Tier B — Capability already half-present

Two features are already paid for in the backend and simply not exposed. They are cheap in a way
the rest of this list is not.

### 5. Spatialization, with X3DAudio already initialized

- `src/driver/xaudio2.swg` calls `X3DAudioInitialize` and stores the handle in `x3DInstance`. That
  handle is never read again. The 3D engine is initialized on every engine creation and does
  nothing.
- Missing above it: a listener, a per-voice position, distance attenuation, and a matrix apply on
  the source voice. X3DAudio computes the output matrix; the module has to feed it and apply the
  result.
- Also missing, and simpler: plain stereo panning. There is no pan control at all, which is the
  cheapest spatial cue there is and the one most applications actually want.

### 6. Filters, with the voice flag already set

- Submix voices are created with `XAUDIO2_VOICE_USEFILTER` in `src/driver/xaudio2.swg`. The
  capability is requested and no API exposes it.
- XAudio2 gives a per-voice low-pass, high-pass, band-pass and notch filter for free once that flag
  is set. Beyond it, XAPO provides reverb and echo.
- A cutoff and resonance on `Voice` and `Bus` is a small surface over a capability that is already
  being paid for on every submix.

---

## Tier C — Breadth

### 7. Engine creation cost on the startup path

- `DriverNative.createNative` does COM initialization, `XAudio2Create`, mastering-voice creation,
  channel-mask query and `X3DAudioInitialize`. Engine creation was previously measured in the 500
  to 950 millisecond range, which dominates the startup of the example scripts that call it —
  `bin/examples/scripts/flappy.swgs`, `invaders.swgs` and `pacman.swgs`.
- Re-measure before acting; then consider deferring device work off the calling thread so the
  application can draw its first frame while the engine comes up.
- Related: no `findings.*` file has an entry for this. If measurement shows the cost is in XAudio2
  rather than in this module, record it there instead.

### 8. Capture and recording

- No input path at all: no capture device, no duplex, no loopback. miniaudio and PortAudio both
  treat capture as a peer of playback.
- This is what a recorder, a voice-chat path, or a level meter would need. It is also a prerequisite
  if `sCapture` ever records video with sound — see that module's roadmap.

### 9. A second platform

- `DriverKind` is `Default`, `NoSound`, `XAudio2`. Off Windows, `Default` resolves to silence.
- The backend boundary in `src/driver/backend.swg` is clean and already has two implementations, so
  a third is additive rather than structural. CoreAudio and ALSA or PulseAudio are the obvious
  targets; WASAPI directly would also remove the XAudio2 dependency on Windows.

### 10. Effects graph

- Buses route and scale gain. They do not process. FMOD, Wwise, SoLoud and miniaudio all expose a
  DSP or node graph where an effect can be inserted on a bus.
- Sequence this after entry 6: a per-voice filter answers most of the need, and an effects graph is
  a much larger commitment. Do not build the graph to get the filter.

---

## Out of scope

**An authoring tool.** FMOD Studio and Wwise are as much authoring applications as they are
runtimes — banks, events, parameters, adaptive music, and a designer-facing editor. That is a
product, not a standard-library module.

**Bundled codec licensing.** Any format added under entry 1 must be a clean-room or
permissively-licensed implementation. Do not vendor a decoder whose terms cannot be satisfied by a
standard library shipped with a compiler.
