# Buses, drivers, and codecs

An [[Audio.Bus]] is a submix node. Route a voice to one or more buses with
[[Audio.Voice.setRooting]], then adjust a bus to affect every voice routed
through it. A bus may itself target a parent bus, which forms a directed mixing
graph.

```swag
let effects = notnull try Audio.Bus.create(2)
defer catch effects.destroy()

let voice = notnull try Audio.Voice.create(&sound)
defer voice.destroy()

try voice.setRooting([effects])
try effects.setVolumeDB(-6)
try voice.play()
```

An empty routing slice sends a voice to the mastering output. Do not destroy a
bus while voices or child buses still depend on it.

[[Audio.DriverKind.Default]] selects the platform backend. Windows uses XAudio2;
other targets and explicit headless runs can use
[[Audio.DriverKind.NoSound]]. Backend-suffixed methods are exposed for backend
integration, but ordinary applications should call the unsuffixed
[[Audio.Voice.setVolume]], [[Audio.Voice.setFrequencyRatio]],
[[Audio.Voice.setRooting]], and [[Audio.Bus.setVolume]] methods.

The codec interface is an extension point for converting a source
[[Audio.SoundFileEncoding]] into a backend-supported encoding. Register codec
implementations with [[Audio.addCodec]] during initialization. Codecs operate on
caller-owned buffers and report both consumed input bytes and produced output
bytes.
