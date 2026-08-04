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
