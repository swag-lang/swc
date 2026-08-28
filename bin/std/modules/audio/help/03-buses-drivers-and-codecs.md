# Buses, drivers, and codecs

An [[Audio.Bus]] is a submix node. Route a voice to one or more buses with
[[Audio.Voice.setRouting]], then adjust a bus to affect every voice routed
through it. A bus may itself target a parent bus, which forms a directed mixing
graph.

```swag
let effects = try Audio.Bus.create(2)!
defer effects.destroy()

let voice = try Audio.Voice.create(&sound)!
defer voice.destroy()

try voice.setRouting([effects])
try effects.setVolumeDb(-6)
try voice.play()
```

An empty routing slice sends a voice to the mastering output. Do not destroy a
bus while voices or child buses still depend on it.

[[Audio.DriverKind.Default]] selects the platform backend. Windows uses XAudio2;
other targets and explicit headless runs can use
[[Audio.DriverKind.NoSound]]. Applications use the backend-independent
[[Audio.Voice.setVolume]], [[Audio.Voice.setFrequencyRatio]],
[[Audio.Voice.setRouting]], and [[Audio.Bus.setVolume]] methods.

The codec interface is an extension point for converting a source
[[Audio.SoundFileEncoding]] into a backend-supported encoding. Register codec
implementations with [[Audio.registerCodec]] during initialization. Codecs operate on
caller-owned buffers and report both consumed input bytes and produced output
bytes.

The built-in packet codecs decode AAC-LC, AC-3, the common independent E-AC-3 profile, DTS Core,
FLAC, MPEG Layer III, Vorbis, Opus, and the Microsoft and IMA ADPCM variants of WAVE without calling
an operating-system media decoder. Layer III covers all three MPEG
versions at every sampling frequency, and a `.mp3` file opens through [[Audio.SoundFile.load]],
which drops the priming its encoder tag states so playback lines up with every other player. The
same call opens `.aac` transport streams and `.ac3`, `.eac3`, and `.dts` elementary streams, each indexed by
walking its frame headers, and `.ogg`, `.oga`, and `.opus` files, indexed by runs of Ogg pages so a
voice restarts a decode on the page before any seek target. A Vorbis stream keeps its encoded
sampling rate and up to eight channels in the WAVE order; an Opus stream plays at 48 kHz whatever
its band, drops the pre-skip its header states, and applies the header's output gain. An ADPCM
WAVE file is indexed by its blocks and decodes to sixteen-bit PCM with the reference nibble
expansion, so it seeks and plays like any other packetized sound. A DTS-HD access unit is decoded through its complete backward-compatible
Core prefix; its extension substream is ignored rather than mistaken for part of that Core frame.
Core frames using high-frequency vector quantization retain their scalar-coded bands and omit the
VQ-coded highest bands, as the format permits for a constrained decoder. Four-tap ADPCM prediction
retains its history across consecutive Core frames.
FLAC is lossless, and a sixteen-bit stream up
to eight channels therefore reaches the mixer as the exact samples that were encoded; a deeper
stream is scaled down to the sixteen bits every packet codec here produces. E-AC-3 streams using
dependent substreams, Adaptive Hybrid Transform, enhanced coupling, spectral extension, or
transient processing fail explicitly instead of producing approximate PCM.
