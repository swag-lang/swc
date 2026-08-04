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
