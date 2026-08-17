#global public

using Core, Core.Errors, Pixel

internal enum ClipSourceKind
{
    None
    Frames
    Memory
    File
}

// Owns or indexes a silent sequence of equal-sized image frames.
//
// A clip created with [[Video.Clip.create]] owns every image added to it. A clip
// decoded from memory owns a copy of the encoded bytes. A file-backed clip keeps
// only the source path and frame offsets; keep that file available while calling
// [[Video.Clip.decodeFrame]].
#[Swag.Opaque]
struct Clip
{
    internal
    {
        sourceKind:   ClipSourceKind
        frameWidth:   s32
        frameHeight:  s32
        rate:         FrameRate
        frames:       Array'Image
        frameOffsets: Array'u64
        encodedBytes: Array'u8
        path:         String
        colorRange:   Y4m.ColorRange
        chromaMode:   Y4m.ChromaMode
    }
}

impl Clip
{
    // Creates an empty clip with fixed geometry and timing.
    //
    // Add at least one matching frame before encoding or saving it. Fails when
    // dimensions are not positive or the frame rate is invalid.
    func create(width, height: s32, frameRate: FrameRate)->Clip fail
    {
        if width <= 0 or height <= 0 do
            fail BadParameterError{"video width and height need positive values"}
        if !frameRate.isValid() do
            fail BadParameterError{"video frame rate needs positive numerator and denominator values"}

        var result: retval
        result.sourceKind  = .Frames
        result.frameWidth  = width
        result.frameHeight = height
        result.rate        = frameRate
        return result
    }

    // Reports whether the clip has valid geometry and timing.
    mtd const isValid()->bool => .frameWidth > 0 and .frameHeight > 0 and .rate.isValid() and .sourceKind != .None

    // Returns the frame width, in pixels.
    mtd const width()->s32 => .frameWidth

    // Returns the frame height, in pixels.
    mtd const height()->s32 => .frameHeight

    // Returns the exact frame rate.
    mtd const frameRate()->FrameRate => .rate

    // Returns the number of frames in the clip.
    mtd const frameCount()->u64 => .sourceKind == .Frames ? .frames.count : .frameOffsets.count

    // Returns the clip duration in seconds.
    mtd const durationInSeconds()->f64
    {
        if !.rate.isValid() do
            return 0
        return cast(f64) .frameCount() * cast(f64) .rate.denominator() / cast(f64) .rate.numerator()
    }

    // Returns the file used by [[Video.Clip.load]], or an empty string otherwise.
    mtd const sourcePath()->string => .path

    // Adds an owned copy of one frame to a created clip.
    //
    // The image dimensions must match the clip. All four 8-bit Pixel RGB and BGR
    // formats are accepted; alpha is retained in memory and discarded only when
    // encoding YUV4MPEG2. Frames cannot be appended to a loaded or decoded clip.
    mtd addFrame(frame: Image) fail
    {
        if .sourceKind != .Frames do
            fail BadParameterError{"frames can only be added to a created clip"}
        if !frame.isValid() do
            fail BadParameterError{"video frame needs allocated pixels"}
        if frame.width != .frameWidth or frame.height != .frameHeight do
            fail BadParameterError{"video frame dimensions do not match the clip"}
        .frames.add(frame)
    }

    // Decodes one frame to an owned RGB8 image.
    //
    // `index` is zero-based and must be smaller than [[Video.Clip.frameCount]].
    // Created clips return a copy of their stored image. File-backed clips reopen
    // their source and read only the selected YUV4MPEG2 payload.
    mtd const decodeFrame(index: u64)->Image fail
    {
        if index >= .frameCount() do
            fail BadParameterError{"video frame index exceeds the clip frame count"}

        switch .sourceKind
        {
        case .Frames: return .frames[index]
        case .Memory: return Y4m.decodeFrame(.encodedBytes.toSlice(), .frameOffsets[index], .frameWidth, .frameHeight, .colorRange, .chromaMode)
        case .File:   return Y4m.decodeFrame(.path.toString(), .frameOffsets[index], .frameWidth, .frameHeight, .colorRange, .chromaMode)
        case .None:   fail BadParameterError{"video clip has no source"}
        }
    }

    // Decodes and indexes a complete encoded memory buffer.
    //
    // `fileName` selects the codec by extension. The returned clip owns a copy of
    // `bytes`, and later frame decoding does not borrow the caller's buffer.
    func decode(fileName: string, bytes: const [..] u8)->Clip fail
    {
        if Path.lowercaseExtension(fileName) != ".y4m" do
            fail UnsupportedFormatError{"no video decoder accepts this file extension"}

        var index = Y4m.index(bytes)
        var result: retval
        result.sourceKind   = .Memory
        result.frameWidth   = index.width
        result.frameHeight  = index.height
        result.rate         = index.rate
        result.colorRange   = index.colorRange
        result.chromaMode   = index.chromaMode
        result.frameOffsets = #move index.frameOffsets
        result.encodedBytes.add(bytes)
        return result
    }

    // Loads and indexes a YUV4MPEG2 file without decoding its frame pixels.
    //
    // The file is reopened by [[Video.Clip.decodeFrame]], so it must remain
    // available and unchanged for the lifetime of the loaded clip.
    func load(fileName: string)->Clip fail
    {
        if Path.lowercaseExtension(fileName) != ".y4m" do
            fail UnsupportedFormatError{"no video decoder accepts this file extension"}

        var index = Y4m.index(fileName)
        var result: retval
        result.sourceKind   = .File
        result.frameWidth   = index.width
        result.frameHeight  = index.height
        result.rate         = index.rate
        result.colorRange   = index.colorRange
        result.chromaMode   = index.chromaMode
        result.frameOffsets = #move index.frameOffsets
        result.path         = fileName
        return result
    }

    // Encodes the clip to an owned segmented memory buffer.
    //
    // `fileName` selects the codec by extension; no file is opened. YUV4MPEG2
    // encoding uses progressive 8-bit 4:4:4 limited-range BT.601 YCbCr and carries
    // no audio. Fails when the clip has no frame.
    mtd const encode(fileName: string)->ConcatBuffer fail
    {
        if Path.lowercaseExtension(fileName) != ".y4m" do
            fail UnsupportedFormatError{"no video encoder accepts this file extension"}
        if !.frameCount() do
            fail InvalidFormatError{"video clip needs at least one frame"}

        var result: retval
        Y4m.encode(&result, me)
        return result
    }

    // Encodes the clip to one contiguous owned byte array.
    mtd const encodeToBytes(fileName: string)->Array'u8 fail
    {
        var buffer = try .encode(fileName)
        buffer.makeLinear()

        var result: retval
        result.add(buffer.toSlice()!)
        return result
    }

    // Encodes the clip and writes it to `fileName`.
    mtd const save(fileName: string) fail
    {
        var result = try .encode(fileName)
        File.writeAllBytes(fileName, result)
    }
}
