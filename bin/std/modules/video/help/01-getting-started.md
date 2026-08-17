# Reading and writing video

[[Video.Clip]] represents a silent timed sequence of equal-sized [[Pixel.Image]] values. The
initial YUV4MPEG2 codec deliberately favors a small, portable implementation over
compression: it stores progressive 8-bit Y, Cb, and Cr planes at full 4:4:4
resolution.

Use [[Video.Clip.load]] for playback. It reads the header and indexes frame payloads, but
does not decode their pixels. [[Video.Clip.decodeFrame]] then reopens the source and reads
only the selected frame. Keep the source file available for as long as frames may
still be requested.

Create an empty clip with fixed geometry and a [[Video.FrameRate]], add matching images,
then call [[Video.Clip.save]]. The writer accepts every 8-bit Pixel RGB or BGR format and drops
alpha. It converts through limited-range BT.601 YCbCr; the decoder also honors the
YUV4MPEG2 full-range tag. A decoded round trip can differ by a few channel values.

YUV4MPEG2 has no audio stream. Audio tracks and synchronization will belong to
future container codecs and will compose with the standard Audio module rather
than adding a second sound implementation here.
