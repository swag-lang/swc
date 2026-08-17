/*
Video reads and writes silent video streams as timed sequences of [[Pixel.Image]]
frames.

The first codec is YUV4MPEG2 (`.y4m`) with progressive 8-bit 4:4:4 YCbCr
frames. File-backed clips index their frame payloads without decoding them, then
materialize one frame at a time through [[Video.Clip.decodeFrame]]. This keeps
playback memory bounded independently of the file duration.

```swag
#import("video")

using Video

let rate = try FrameRate.create(24, 1)
var clip = try Clip.create(320, 180, rate)
let frame = Pixel.Image.create(320, 180, .RGB8)
try clip.addFrame(frame)
try clip.save("preview.y4m")

let loaded = try Clip.load("preview.y4m")
let first = try loaded.decodeFrame(0)
```

YUV4MPEG2 carries no audio. Alpha is discarded during encoding, and decoded
frames use [[Pixel.PixelFormat.RGB8]]. Malformed streams, unsupported chroma or
interlacing, inconsistent frames, and file access errors use Swag's normal
`fail` mechanism.
*/

#import("core")
#import("pixel")

#run
{
    let itf = @compiler
    let cfg = itf.getBuildCfg()!
    cfg.moduleVersion   = #swcversion
    cfg.moduleRevision  = #swcrevision
    cfg.moduleBuildNum  = #swcbuildnum
    cfg.moduleNamespace = "Video"
    cfg.backendKind     = .SharedLibrary
    cfg.repoPath        = "https://github.com/swag-lang/swc/blob/master/bin/std/modules/video"

    cfg.genDoc.kind         = .Api
    cfg.genDoc.outputName   = "std.video"
    cfg.genDoc.titleContent = "Video"
    cfg.genDoc.titleToc     = "Video documentation"
    cfg.genDoc.icon         = "favicon.svg"
    cfg.genDoc.css          = "css/style.css"
}
