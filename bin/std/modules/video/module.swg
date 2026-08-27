/*
Video reads and writes timed sequences of [[Pixel.Image]] frames. File-backed ISO-BMFF and
Matroska readers also expose streamed sound tracks through [[Audio.SoundFile]] and timed text
through [[Video.Subtitle.Track]]. Standalone subtitle documents use the same track and cue model.

Reading and writing are streamed: [[Video.Reader]] opens a stream by reading its
metadata and decodes one frame at a time, and [[Video.Writer]] encodes one frame
at a time into its destination. Encoded media payloads remain in their source;
indexed containers retain compact sample tables while decoding keeps only the
active picture, codec references, and bounded audio buffers. [[Video.Clip]] is
the other half of the picture — the frames a program builds in memory before
encoding them.

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
Four codecs ship in the box:

- YUV4MPEG2 (`.y4m`) reads progressive 8-bit monochrome, 4:2:0, 4:2:2 and 4:4:4
  YCbCr frames and writes 4:4:4 ones. It does not compress, so it favors a small
  implementation over the size of what it produces.
- AVI (`.avi`) reads Motion JPEG, MPEG-4 Part 2, and uncompressed frames, exposes integer PCM sound
  tracks, and writes Motion JPEG pictures. A coded stream states its codec through the bitmap
  header of the container and its setup headers inside the stream, and stores a bidirectional plane
  behind the plane it refers forward to, which is what this container's lack of a decoding order
  costs. It seeks through the index the container carries rather than
  through the frames themselves, so a seek costs one frame whatever the length of the file.
- ISO-BMFF (`.mp4`, `.m4v`, and `.mov`) reads Motion JPEG, H.264, and H.265 pictures, writes
  Motion JPEG, and exposes AAC-LC mono/stereo audio. It expands compact sample tables into direct
  packet offsets while payloads remain in the file. Exact composition timestamps are retained for
  variable-rate playback and coded display reordering.
- Matroska (`.mkv`) reads H.264, H.265, and MPEG-4 Part 2 pictures and exposes every AAC-LC, AC-3,
  independent E-AC-3, DTS Core, FLAC, and MPEG Layer III audio track with up to eight channels. A picture
  track remuxed from a legacy file is read as well: such a track names its codec through a Video
  for Windows header, states its setup headers inside the stream rather than in the container, and
  may store a bidirectional plane behind the plane it refers forward to. Display order is then
  taken from the clock the stream states, not from the order the container hands samples over.
  Frames stored without the bytes they all begin with, which is what mkvmerge does by default to
  several codecs, are handed to the decoder whole; a track compressed or encrypted any other way is
  not offered. A file whose tail never made it to disk is read as far as it goes. Matroska `CodecDelay` is removed from the audible timeline.
  Opening reads only seek, track, and cue metadata. Decoding advances one foreground demux cursor
  through complete cluster windows as playback reaches them; random access restarts it at the
  preceding video cue and reconstructs the coded prediction through the requested picture. No
  full-file scan competes with playback. Sound tracks become available when that progressive
  cursor reaches their playback window; `S_TEXT/UTF8`, `S_TEXT/ASS`, and `S_TEXT/SSA` subtitle
  tracks are exposed on that same media timeline. The complete indexes continue in the
  background, and work may be interrupted through
  [[Video.Reader.requestCancel]]. Media payloads stay in the file.

[[Video.Subtitle.Track.loadOwned]] decodes SubRip (`.srt`), WebVTT (`.vtt`), ASS/SSA (`.ass` and
`.ssa`), LRC (`.lrc`), and MicroDVD (`.sub`) documents. UTF-8, UTF-16, UTF-32, and Windows-1252
text are detected. The decoder keeps cue timing and readable text while leaving font, color,
position, outline, and synchronization choices to the player.

Decoding and encoding are separate implementations of a format, under `src/decode`
and `src/encode`, laid out as the Pixel image codecs are. A format that has
something to choose takes an options structure the same way they do, such as
[[Avi.EncodeOptions]] and [[Mp4.EncodeOptions]].

Unsupported picture or sound codecs fail or remain unavailable rather than being mistaken for
decoded media.
Alpha is discarded during encoding, and decoded frames use
[[Pixel.PixelFormat.RGB8]]. Malformed streams, unsupported codecs, inconsistent
frames, and file access errors use Swag's normal `fail` mechanism.
*/

#import("core")
#import("audio")
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
