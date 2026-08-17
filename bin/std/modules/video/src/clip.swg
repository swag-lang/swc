#global public

using Core, Core.Errors, Pixel

// Owns a silent sequence of equal-sized image frames held in memory.
//
// A clip is what a program builds when it produces a video: frames are added in playback
// order, then encoded. It holds every frame it was given, so its memory cost is the whole
// clip; reading an existing stream, of any length, is [[Video.Reader]] instead.
#[Swag.Opaque]
struct Clip
{
    internal
    {
        frameWidth:  s32
        frameHeight: s32
        rate:        FrameRate
        frames:      Array'Image
    }
}

impl Clip
{
    // Creates an empty clip with fixed geometry and timing.
    //
    // Add at least one matching frame before encoding or saving it. Fails when dimensions are
    // not positive or the frame rate is invalid.
    func create(width, height: s32, frameRate: FrameRate)->Clip fail
    {
        if width <= 0 or height <= 0 do
            fail BadParameterError{"video width and height need positive values"}
        if !frameRate.isValid() do
            fail BadParameterError{"video frame rate needs positive numerator and denominator values"}

        var result: retval
        result.frameWidth  = width
        result.frameHeight = height
        result.rate        = frameRate
        return result
    }

    // Reports whether the clip has valid geometry and timing.
    mtd const isValid()->bool => .frameWidth > 0 and .frameHeight > 0 and .rate.isValid()

    // Returns the frame width, in pixels.
    mtd const width()->s32 => .frameWidth

    // Returns the frame height, in pixels.
    mtd const height()->s32 => .frameHeight

    // Returns the exact frame rate.
    mtd const frameRate()->FrameRate => .rate

    // Returns the number of frames in the clip.
    mtd const frameCount()->u64 => .frames.count

    // Returns the clip duration in seconds.
    mtd const durationInSeconds()->f64
    {
        if !.rate.isValid() do
            return 0
        return cast(f64) .frameCount() * cast(f64) .rate.denominator() / cast(f64) .rate.numerator()
    }

    // Adds an owned copy of one frame to the clip.
    //
    // The image dimensions must match the clip. All four 8-bit Pixel RGB and BGR formats are
    // accepted; alpha is retained in memory and discarded only when encoding a format that
    // does not carry it.
    mtd addFrame(frame: Image) fail
    {
        if !frame.isValid() do
            fail BadParameterError{"video frame needs allocated pixels"}
        if frame.width != .frameWidth or frame.height != .frameHeight do
            fail BadParameterError{"video frame dimensions do not match the clip"}
        .frames.add(frame)
    }

    // Returns an owned copy of the frame at `index`, as it was added.
    //
    // `index` is zero-based and must be smaller than [[Video.Clip.frameCount]]. The clip keeps
    // its own frame, so the result can outlive it and can be modified freely.
    mtd const frame(index: u64)->Image fail
    {
        if index >= .frameCount() do
            fail BadParameterError{"video frame index exceeds the clip frame count"}
        return .frames[index]
    }

    // Encodes the clip to an owned segmented memory buffer.
    //
    // `fileName` selects the codec by extension; no file is opened. The result holds the whole
    // encoded stream, which is what a clip already is; [[Video.Clip.save]] streams to a file
    // instead. Fails when the clip has no frame.
    //
    // `options` is `null` for the defaults of the selected format, or points to that format's
    // options structure, such as [[Avi.EncodeOptions]].
    mtd const encode(fileName: string, options: #null any = null)->ConcatBuffer fail
    {
        .validateEncode(fileName)

        var result: retval
        var writer = Writer.createMemory(fileName, &result, .frameWidth, .frameHeight, .rate, options)
        .write(&writer)
        return result
    }

    // Encodes the clip to one contiguous owned byte array.
    mtd const encodeToBytes(fileName: string, options: #null any = null)->Array'u8 fail
    {
        var buffer = try .encode(fileName, options)
        buffer.makeLinear()

        var result: retval
        result.add(buffer.toSlice()!)
        return result
    }

    // Encodes the clip and writes it to `fileName`.
    //
    // Frames are encoded and written one at a time, so saving never holds the encoded stream in
    // addition to the clip.
    //
    // ## Example
    //
    // ```swag
    // try clip.save("preview.avi", Video.Avi.EncodeOptions{quality: 80})
    // ```
    mtd const save(fileName: string, options: #null any = null) fail
    {
        .validateEncode(fileName)

        var writer = Writer.create(fileName, .frameWidth, .frameHeight, .rate, options)
        .write(&writer)
    }

    // Rejects a request no clip can satisfy, before a stream is created or a file is opened.
    //
    // The extension is answered first: a clip is told that a format cannot be written whether or
    // not it holds frames, and adding one never turns that answer into a different error.
    private mtd const validateEncode(fileName: string) fail
    {
        if !Writer.canCreate(fileName) do
            fail UnsupportedFormatError{"no video encoder accepts this file extension"}
        if !.frameCount() do
            fail InvalidFormatError{"video clip needs at least one frame"}
    }

    // Feeds every frame to `writer` and finishes the stream.
    private mtd const write(writer: *Writer) fail
    {
        for frame in .frames do
            writer.addFrame(frame[])
        writer.end()
    }
}
