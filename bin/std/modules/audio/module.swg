/*
Audio streams decoded sound through a process-wide audio engine. It loads PCM, floating-point, and
ADPCM `.wav`, `.flac`, `.mp3`, `.aac`, `.ac3`, `.eac3`, `.dts`, `.ogg`, and `.opus` files directly, and
container readers can expose indexed AAC-LC, AC-3, E-AC-3, DTS Core, FLAC, Layer III, Vorbis, and
Opus access units or scattered PCM chunks without copying their media payload. A compressed file is
indexed, never loaded: opening one walks its frame headers and the audio stays on disk. The
compressed decoders are implemented in Swag and add no platform codec dependency.

DTS-HD access units play through their backward-compatible Core prefix. The decoder does not
reconstruct the lossless extension substream.

The high-level API revolves around three objects: [[Audio.SoundFile]] describes
decoded or streamable source data, [[Audio.Voice]] controls one playback
instance, and [[Audio.Bus]] groups voices for shared volume and routing. The
default Windows backend is XAudio2; Linux uses FAudio through the SDL audio device driver.
[[Audio.Wav.Writer]] writes mono or stereo PCM16 recordings in bounded memory, updates a
playable file prefix on every flush, fills silence gaps, and can resume from that prefix after an
interruption.
[[Audio.Flac.Writer]] compresses PCM16 recordings into resumable native FLAC files.
[[Audio.Resampler]] converts streaming PCM between sample rates and adjusts its ratio for clock drift.
[[Audio.Aac.Encoder]] encodes mono or stereo PCM16 to AAC-LC packets in full or voice bandwidth.
[[Audio.Aac.StreamEncoder]] buffers arbitrary PCM16 chunks into packets and reports the 1024-frame priming delay.
[[Audio.Aac.SilenceEncoder]] supplies AAC-LC silence packets during a lost capture source.
[[Audio.CaptureQueue]] transfers timestamped PCM blocks from a capture backend in bounded memory,
reporting gaps, overflows, and source restoration.
[[Audio.CapturePcmFeeder]] converts native PCM16, float32, and silent packets into that queue.
On Windows, `CaptureMicrophone` opens the default input and `CaptureOutputLoopback` reads the
system output mix through native shared-mode WASAPI; device execution still needs validation
on a Windows machine. The loopback path emits bounded silence when the output is inactive.
[[Audio.CaptureAacTrack]] turns those blocks and missing intervals into timestamped AAC-LC packets
with bounded memory and reports encoder priming for a container timeline.
[[Audio.CaptureClockDrift]] measures a source's sample-clock drift from raw frame positions and
monotonic timestamps, then applies its estimate to a streaming resampler.
[[Audio.CaptureRecovery]] schedules device reopen attempts while preserving an outage as a sample gap.
Linux requires `libFAudio.so.0` and its SDL dependencies; device acquisition failures are reported.
The Linux backend accepts one through eight source or bus channels, including mono/stereo
conversion and multiple or nested bus routes. Source sample rates range from 1000 to 200000 Hz,
and frequency ratios from 1/1024 through 2. Values outside these ranges fail explicitly.
[[Audio.DriverKind.NoSound]] provides the
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
#static if #os == Swag.TargetOs.Linux do
    #import("faudio")
#static if #os == Swag.TargetOs.Windows do
    #import("xaudio2")

#run
{
    let itf = Swag.compiler()
    let cfg = unwrap itf.getBuildCfg()
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
