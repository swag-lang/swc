/*
Video reads and writes silent video streams as timed sequences of [[Pixel.Image]]
frames.

Reading and writing are streamed: [[Video.Reader]] opens a stream by reading its
header alone and decodes one frame at a time, and [[Video.Writer]] encodes one
frame at a time into its destination. Neither holds the encoded stream, so both
cost the memory of a frame rather than the memory of a file, whatever its length.
[[Video.Clip]] is the other half of the picture — the frames a program builds in
memory before encoding them.

```swag
#import("video")

using Video

let rate  = try FrameRate.create(24, 1)
var clip  = try Clip.create(320, 180, rate)
let frame = Pixel.Image.create(320, 180, .RGB8)
try clip.addFrame(frame)
try clip.save("preview.y4m")

var reader = try Reader.open("preview.y4m")
var picture: Pixel.Image
for index in reader.frameCount() do
    try reader.decodeFrameInto(&picture, index)
```

A format is a codec registered against [[Video.IDecoder]] and [[Video.IEncoder]],
selected by filename extension; both read and write through [[Video.Source]] and
[[Video.Sink]], which are what make a codec independent of files and memory alike.
Two codecs ship in the box:

- YUV4MPEG2 (`.y4m`) reads progressive 8-bit monochrome, 4:2:0, 4:2:2 and 4:4:4
  YCbCr frames and writes 4:4:4 ones. It does not compress, so it favors a small
  implementation over the size of what it produces.
- AVI (`.avi`) reads Motion JPEG and uncompressed frames and writes Motion JPEG
  ones. It seeks through the index the container carries rather than through the
  frames themselves, so a seek costs one frame whatever the length of the file.

Neither format carries audio. Alpha is discarded during encoding, and decoded
frames use [[Pixel.PixelFormat.RGB8]]. Malformed streams, unsupported codecs,
inconsistent frames, and file access errors use Swag's normal `fail` mechanism.
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
