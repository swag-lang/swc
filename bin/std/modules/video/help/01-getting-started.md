# Reading and writing video

A video is read as a stream and written as a stream. [[Video.Reader]] opens a file by
reading its header alone and decodes one frame at a time; [[Video.Writer]] encodes one frame
at a time into its destination. Neither ever holds the encoded stream, so a video of any
length costs the memory of a single frame. [[Video.Clip]] is the other half: the frames a
program builds in memory before encoding them.

## Playing a stream

```swag
var reader = try Video.Reader.open("clip.y4m")
var frame: Pixel.Image
for index in reader.frameCount() do
    try reader.decodeFrameInto(&frame, index)
```

[[Video.Reader.decodeFrameInto]] reuses the image it is given, so decoding a whole video
allocates one frame in total. Decoding frames in order never seeks; decoding them out of
order costs whatever random access costs in that format. [[Video.Reader.frameCount]] returns
zero when the format cannot report a count without decoding the stream, and a stream read
that way ends by failing rather than by returning a frame.

The file stays open until the reader is closed, so it must remain available and unchanged.
[[Video.Reader.openMemory]] reads an encoded stream already held in memory, borrowing it
rather than copying it.

## Producing a video

Create an empty clip with fixed geometry and a [[Video.FrameRate]], add matching images,
then call [[Video.Clip.save]]. Use [[Video.Writer]] directly when the frames are produced
one at a time and never all exist together, which is what a recorder or a renderer does.

The encoders accept every 8-bit Pixel RGB or BGR format and drop alpha. A decoded round trip
differs from what was written by a few channel values, and by more than that on a format that
compresses.

## Choosing a format

The extension of the file selects the codec, so choosing one is choosing a name.

| Extension | Reads | Writes | Costs |
| --- | --- | --- | --- |
| `.y4m` | 8-bit monochrome, 4:2:0, 4:2:2 and 4:4:4 planar YCbCr | 4:4:4 planar YCbCr | Nothing is lost, and nothing is compressed either: one second of 720p costs about forty megabytes. |
| `.avi` | Motion JPEG, and uncompressed 24- and 32-bit frames | Motion JPEG | Each frame is a JPEG image, so the file is one to two orders of magnitude smaller and the picture loses what JPEG loses. |
| `.mp4`, `.m4v`, `.mov` | Motion JPEG in ISO-BMFF sample tables | Motion JPEG | Every frame is independently seekable. H.264 and other inter-frame codecs are identified and refused until their picture decoders exist. |

All three code every frame on its own, so they seek anywhere at the cost of one frame: YUV4MPEG2
computes the offset from the constant size of a frame, AVI reads it from the index the container
carries, and ISO-BMFF expands its chunk and sample tables once when the stream opens. None holds a
decoded frame between two calls, which is why decoding a stream out of order costs the same as
decoding it in order.

## Controlling how a stream is encoded

A format that has something to configure takes an options structure, exactly as the Pixel image
encoders do. Pass it to [[Video.Clip.save]], [[Video.Clip.encode]] or [[Video.Writer.create]];
passing nothing takes the defaults of the selected format.

```swag
try clip.save("capture.avi", Video.Avi.EncodeOptions{quality: 80})
```

[[Avi.EncodeOptions]] and [[Mp4.EncodeOptions]] both select the JPEG quality of their Motion JPEG
frames. YUV4MPEG2 writes one plane layout and one colour range and so has nothing to choose.

## Adding a format

A format is a codec registered against [[Video.IDecoder]] and [[Video.IEncoder]] and selected
by filename extension, exactly like the image codecs of the Pixel module — and laid out the same
way, one file per format on each side:

```
src/decode/reader.swg    the registry, and Video.Reader
src/decode/y4m.swg       Y4m.Decoder, and the layout of the format
src/decode/avi.swg       Avi.Decoder, and the layout of the container
src/decode/mp4.swg       Mp4.Decoder, and the ISO-BMFF sample tables
src/encode/writer.swg    the registry, and Video.Writer
src/encode/y4m.swg       Y4m.Encoder
src/encode/avi.swg       Avi.Encoder
src/encode/mp4.swg       Mp4.Encoder
```

Decoding and encoding one format are two independent implementations that share only its binary
layout, and that layout is declared on the decoding side, where reading it comes first.

A codec reads through [[Video.Source]] and writes through [[Video.Sink]], which are what keep it
independent of files and memory alike, and it implements random access itself: a fixed frame size
computes an offset, an indexed container reads the index, and a format with inter-coded frames
seeks to a keyframe and decodes forward.

A container whose header carries a total it only learns at the end — the size of the file, the
number of frames, the offset of an index — reserves that field when it writes the header and
rewrites it with [[Video.Sink.patch]] once the last frame lands. That is what keeps a writer at
the memory cost of one frame instead of the cost of the result, and it is how the AVI encoder
works.

## What a codec is tested against

Every decoding test reads a file from `src/tests/datas/`, and none of those files is produced
by this module: a codec that only reads back what it wrote proves nothing about the files people
have. The corpus holds a camera recording, sequences from the standard research collection, one
synthetic clip encoded in the tested layouts by ffmpeg, and copies of that clip with a container
shape injected into them that no single writer produces. `datas/SOURCES.md` states where each one
came from, what it exercises, and under what terms it is redistributed.

The current reader exposes no audio stream. ISO-BMFF audio tracks are skipped while the Motion
JPEG picture track remains playable. Audio-track decoding and synchronization will compose with
the standard Audio module rather than adding a second sound implementation here.
