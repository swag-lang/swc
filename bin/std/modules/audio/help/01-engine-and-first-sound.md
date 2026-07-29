# Engine and first sound

An Audio application owns one process-wide engine. Call
[[Audio.createEngine]] before creating voices or buses, and pair it with
[[Audio.destroyEngine]] at the outermost scope that uses audio.

```swag
#import("audio")

using Audio

try createEngine()
defer destroyEngine()

let sound = try SoundFile.load("assets/click.wav")
try Voice.play(&sound)
```

[[Audio.Voice.play]] is the fire-and-forget path: it creates a voice, starts
playback, and requests automatic destruction when playback stops. Keep the
returned [[Audio.Voice]] only when you need to change playback after it starts.

## Run without an audio device

Use [[Audio.createNoSoundEngine]] in tests, command-line tools, and CI jobs. It
keeps file loading, voice state, routing validation, and lifetime behavior
available without depending on audio hardware.

```swag
try createNoSoundEngine()
defer destroyEngine()

let sound = try SoundFile.load("fixtures/alert.wav")
let voice = notnull try Voice.create(&sound)
try voice.play()
try voice.stop()
voice.destroy()
```

> WARNING: [[Audio.destroyEngine]] invalidates the native resources behind all
> remaining voices and buses. Finish or destroy those objects first.
