/*
Audio loads WAV files and plays them through a process-wide audio engine.

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

Failures use normal Swag error propagation. Loading currently accepts WAV
files; unsupported containers or encodings fail instead of being guessed.
*/

#import("core")
#static if #os == Swag.TargetOs.Windows do
    #import("xaudio2")

#run
{
    let itf = @compiler
    let cfg = notnull itf.getBuildCfg()
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
    cfg.genDoc.css = "css/style.css"
}
