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

Both code every frame on its own, so both seek anywhere at the cost of one frame: YUV4MPEG2
computes the offset from the constant size of a frame, and AVI reads it from the index the
container carries. Neither holds a decoded frame between two calls, which is why decoding a
stream out of order costs the same as decoding it in order.

## Adding a format

A format is a codec registered against [[Video.IDecoder]] and [[Video.IEncoder]] and selected
by filename extension, exactly like the image codecs of the Pixel module. A codec reads through
[[Video.Source]] and writes through [[Video.Sink]], which are what keep it independent of files
and memory alike, and it implements random access itself: a fixed frame size computes an offset,
an indexed container reads the index, and a format with inter-coded frames seeks to a keyframe
and decodes forward.

A container whose header carries a total it only learns at the end — the size of the file, the
number of frames, the offset of an index — reserves that field when it writes the header and
rewrites it with [[Video.Sink.patch]] once the last frame lands. That is what keeps a writer at
the memory cost of one frame instead of the cost of the result, and it is how the AVI encoder
works.

Neither format has an audio stream. Audio tracks and synchronization will belong to future
container codecs and will compose with the standard Audio module rather than adding a second
sound implementation here.
