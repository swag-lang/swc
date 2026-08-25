/*
Audio streams decoded sound through a process-wide audio engine. It loads PCM and floating-point
WAV files directly, and container readers can expose indexed AAC-LC, AC-3, E-AC-3, and FLAC
access units or scattered PCM chunks without copying their media payload. The compressed decoders are
implemented in Swag and add no platform codec dependency.

The high-level API revolves around three objects: [[Audio.SoundFile]] describes
decoded or streamable source data, [[Audio.Voice]] controls one playback
instance, and [[Audio.Bus]] groups voices for shared volume and routing. The
default Windows backend is XAudio2; [[Audio.DriverKind.NoSound]] provides the
same lifecycle without opening an audio device.

Create the engine before creating voices or buses. Destroying the engine stops
and releases any remaining playback objects. A fire-and-forget voice created by
[[Audio.Voice.play]] destroys itself at the end of playback.

```swag
#import("audio")

using Audio

try createEngine()
defer destroyEngine()

let sound = try SoundFile.load("assets/notify.wav")
try Voice.play(&sound)
```

Voices provide sample-frame seeking and an output-device playback cursor suitable for an
audio-master video clock. Failures use normal Swag error propagation; unsupported containers and
encodings fail instead of being guessed.
*/

#import("core")
#static if #os == Swag.TargetOs.Windows do
    #import("xaudio2")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()!
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Audio"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/audio"

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "std.audio"
    cfg.genDoc.titleContent = "Audio"
    cfg.genDoc.titleToc     = "Audio documentation"
    cfg.genDoc.icon         = "favicon.svg"
    cfg.genDoc.css          = "css/style.css"
}
