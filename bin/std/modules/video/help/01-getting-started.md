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

The encoder accepts every 8-bit Pixel RGB or BGR format and drops alpha. It converts through
limited-range BT.601 YCbCr; the decoder also honors the YUV4MPEG2 full-range tag. A decoded
round trip can differ by a few channel values.

## Adding a format

A format is a codec registered against [[Video.IDecoder]] and [[Video.IEncoder]] and selected
by filename extension, exactly like the image codecs of the Pixel module. A codec reads through
[[Video.Source]] and writes through [[Video.Sink]], which are what keep it independent of files
and memory alike, and it implements random access itself: a fixed frame size computes an offset,
while a compressed format seeks to a keyframe and decodes forward.

The codec in the box is YUV4MPEG2, which deliberately favors a small, portable implementation
over compression. Its decoder accepts progressive 8-bit monochrome, 4:2:0 JPEG/MPEG-2/PAL-DV,
4:2:2, and 4:4:4 planar streams, and its encoder always writes 4:4:4 frames.

YUV4MPEG2 has no audio stream. Audio tracks and synchronization will belong to future container
codecs and will compose with the standard Audio module rather than adding a second sound
implementation here.
