# Loading, streaming, and voices

[[Audio.SoundFile.load]] always reads and validates the WAV header. With the
default `preloadData = true`, it also keeps the audio payload in memory. Pass
`preloadData = false` for long sounds that should be read from disk while they
play.

```swag
let music = try Audio.SoundFile.load("assets/music.wav", preloadData = false)
let voice = try Audio.Voice.create(&music)!
defer voice.destroy()

try voice.setVolume(0.35)
try voice.play(.Loop)
```

The [[Audio.SoundFile]] must outlive every [[Audio.Voice]] created from it.
Streaming voices also keep the source path and open the file on demand.

Container modules can create indexed packet streams with
[[Audio.SoundFile.openPacketStream]]. AAC-LC supports one to six channels; AC-3 and independent
E-AC-3 support one to six channels. All three decode to interleaved 16-bit PCM in the module's
native Swag codecs. `leadingTrimFrames` removes codec priming from the public timeline, so frame
zero and a seek to frame zero begin at the first audible sample.

[[Audio.SoundFile.readPayload]] reads an owned, bounded range without changing a
voice's streaming position. It is suitable for background analysis such as a
waveform: walk the payload in small blocks and publish partial results while the
voice remains free to start immediately.

Use [[Audio.Voice.pause]] to preserve the current playback position and
[[Audio.Voice.play]] to resume. [[Audio.Voice.stop]] ends the current playback
and rewinds it to the beginning;
when [[Audio.VoicePlayFlags.DestroyOnStop]] is active it also schedules the
voice for destruction.

Volume methods without a suffix use a linear gain from `0` to `1`. The `Db`
variants use decibels, where `0 dB` is unity gain and `-100 dB` maps to silence.
Pitch control is expressed as a frequency ratio and requires
[[Audio.VoiceCreateFlags.PitchControl]] on backends that need that capability
declared when the voice is created.
