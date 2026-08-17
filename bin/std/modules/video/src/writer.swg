#global public

using Core, Core.Errors, Pixel

// One registered encoder: the format it writes, and the type that writes it.
internal struct EncoderDesc
{
    format: StreamFormat
    type:   const *Swag.TypeInfoStruct
}

// Encodes one video format, one frame at a time, into a byte sink.
//
// An encoder instance is created per [[Video.Writer]] and keeps whatever state its format
// needs between frames, including the scratch storage of one frame. It never accumulates the
// encoded stream: everything it produces goes to the [[Video.Sink]] it is handed, so writing
// a long video costs the memory of one frame.
//
// `begin`, `addFrame` and `end` are called in that order, exactly once for the first and the
// last. A format whose header needs a value known only at the end — a frame count, a total size,
// an index — writes it in `end`, either as a trailer, or by reserving the field in the header and
// rewriting it with [[Video.Sink.patch]] once the last frame is written.
interface IEncoder
{
    // Describes the format this encoder writes.
    //
    // The registry stores the result once, at registration, and derives extension matching
    // from it. It is called on an encoder with no instance behind it, so it must return a
    // constant and must not read the encoder's own state.
    mtd format()->StreamFormat

    // Writes the stream header for a stream of the geometry and rate `info` describes.
    //
    // `info.frameCount` is zero here: a writer accepts frames until it is ended, so the count
    // is not known when the header is written.
    mtd begin(sink: *Sink, info: StreamInfo) fail

    // Encodes one frame and appends it to the stream.
    //
    // The writer has already checked that the image is valid and has the geometry the stream was
    // opened with. Fail for what only the format knows, such as a pixel format it cannot encode.
    mtd addFrame(sink: *Sink, image: Image) fail

    // Finishes the stream, writing whatever trailer the format needs.
    mtd end(sink: *Sink) fail
}

// Encodes frames into a video stream without holding the stream in memory.
//
// A writer owns its sink and its encoder instance. Frames are appended in playback order and
// must all have the geometry the writer was created with; [[Video.Writer.end]] finishes the
// stream and is what decides whether it is complete, so its failure must be handled rather
// than left to destruction.
#[Swag.NoCopy]
struct Writer
{
    internal
    {
        sink:        Sink                                 // Bytes of the encoded stream.
        info:        StreamInfo                           // Geometry and rate the stream was opened with.
        format:      StreamFormat                         // Format claimed by the selected encoder.
        encoder:     #null IEncoder                       // Encoder instance owned by this writer.
        encoderType: #null const *Swag.TypeInfoStruct     // Concrete encoder type, used to release it.
        frames:      u64                                  // Number of frames appended so far.
        isEnded:     bool                                 // Whether the stream was finished.
    }
}

impl Writer
{
    internal var encoders: Array'EncoderDesc

    // Registers an encoder type unless it is already present.
    //
    // `T` must implement [[Video.IEncoder]]. Registration stores its format and its type;
    // instances are created on demand, one per open writer.
    func(T) registerEncoder()
    {
        #assert(Reflection.hasInterface(#typeof(T), IEncoder))

        registerEncoderImplementation(#typeof(T), @mkinterface(null, #typeof(T), IEncoder))
    }

    // Non-generic bridge used by registerEncoder after its body is instantiated in the caller's
    // module. The registry itself remains module-internal.
    #[Swag.NoDoc]
    func registerEncoderImplementation(type: const *Swag.TypeInfoStruct, itf: IEncoder)
    {
        for encoder in encoders where encoder.type == type do
            return
        encoders.add({itf.format(), type})
    }

    // Returns the format written by each registered encoder, in registration order.
    //
    // The result is owned by the caller and is a snapshot: registering another encoder
    // afterwards does not change it. Use it to build the format list of a save dialog.
    func encodableFormats()->Array'StreamFormat
    {
        var result: retval
        result.reserve(encoders.count)
        for encoder in encoders do
            result.add(encoder.format)
        return result
    }

    // Reports whether a registered encoder claims `fileName`, by its extension alone.
    func canCreate(fileName: string)->bool => findEncoder(fileName) != null

    // Returns the registered encoder claiming `fileName`, or `null` when none does.
    internal func findEncoder(fileName: string)->#null const *EncoderDesc
    {
        for encoder in encoders where encoder.format.matches(fileName) do
            return encoder
        return null
    }

    // Creates `fileName` and writes the stream header for the given geometry and rate.
    //
    // The extension selects the encoder. Frames are written as they are appended, so the file
    // grows by one frame at a time and the writer never holds more than one.
    //
    // ## Example
    //
    // ```swag
    // let rate   = try Video.FrameRate.create(30, 1)
    // var writer = try Video.Writer.create("capture.y4m", 640, 480, rate)
    // var frame  = Pixel.Image.create(640, 480, .RGB8)
    // for index in 90'u64
    // {
    //     frame.fill(Pixel.Color.fromRgb(cast(u8) index, 64, 128))
    //     try writer.addFrame(frame)
    // }
    //
    // try writer.end()
    // ```
    func create(fileName: string, width, height: s32, frameRate: FrameRate)->Writer fail
    {
        var result: retval
        result.validate(fileName, width, height, frameRate)
        result.sink = Sink.createFile(fileName)
        result.start(fileName)
        return result
    }

    // Encodes into `buffer` instead of a file.
    //
    // `fileName` selects the encoder by extension; no file is opened. `buffer` is borrowed,
    // must stay valid until the writer is ended, and holds the whole encoded stream, so this
    // is for a stream a caller already knows is bounded.
    func createMemory(fileName: string, buffer: *ConcatBuffer, width, height: s32, frameRate: FrameRate)->Writer fail
    {
        var result: retval
        result.validate(fileName, width, height, frameRate)
        result.sink = Sink.createMemory(buffer)
        result.start(fileName)
        return result
    }

    // Rejects a geometry or a rate no stream can carry, before anything is created.
    private mtd validate(fileName: string, width, height: s32, frameRate: FrameRate) fail
    {
        if width <= 0 or height <= 0 do
            fail BadParameterError{"video width and height need positive values"}
        if !frameRate.isValid() do
            fail BadParameterError{"video frame rate needs positive numerator and denominator values"}
        if !canCreate(fileName) do
            fail UnsupportedFormatError{"no video encoder accepts this file extension"}

        .info.width     = width
        .info.height    = height
        .info.frameRate = frameRate
    }

    // Selects the encoder for `fileName`, creates its instance, and writes the stream header.
    private mtd start(fileName: string) fail
    {
        let selected = findEncoder(fileName)!
        .format      = selected.format
        .encoderType = selected.type
        .encoder     = @mkinterface(Memory.new(selected.type), selected.type, IEncoder)
        .encoder.begin(&.sink, .info)
    }

    // Releases the encoder instance and the sink when the writer leaves scope.
    //
    // A writer dropped without [[Video.Writer.end]] leaves an unfinished stream behind; that is
    // the failure path, not a way to abandon a stream quietly.
    mtd opDrop()
    {
        .release()
    }

    // Appends one encoded frame to the stream.
    //
    // The image must have the geometry the writer was created with. All four 8-bit Pixel RGB
    // and BGR formats are accepted; whether alpha survives depends on the format being written.
    mtd addFrame(image: Image) fail
    {
        if .isEnded do
            fail BadParameterError{"video frames cannot be added to an ended stream"}
        if !.encoder do
            fail BadParameterError{"video writer has no open stream"}
        if !image.isValid() do
            fail BadParameterError{"video frame needs allocated pixels"}
        if image.width != .info.width or image.height != .info.height do
            fail BadParameterError{"video frame dimensions do not match the stream"}

        .encoder.addFrame(&.sink, image)
        .frames += 1
    }

    // Finishes the stream and releases everything it held.
    //
    // Only a stream that ended without failing is complete. Repeated calls do nothing.
    mtd end() fail
    {
        if .isEnded do
            return
        if !.encoder do
            fail BadParameterError{"video writer has no open stream"}

        .isEnded = true
        .encoder.end(&.sink)
        .sink.close()
        .release()
    }

    // Returns the number of frames appended so far.
    mtd const frameCount()->u64 => .frames

    // Returns the format of the encoded stream.
    mtd const streamFormat()->StreamFormat => .format

    // Returns the file the writer streams, or an empty string for a memory stream.
    mtd const sourcePath()->string => .sink.sourcePath()

    // Releases the encoder instance. The sink closes itself with the writer.
    private mtd release()
    {
        if !.encoder do
            return

        let type     = .encoderType!
        let instance = @dataof(.encoder)!
        if type.opDrop do
            type.opDrop(instance)
        Memory.free(instance, cast(u64) type.sizeof)
        .encoder     = null
        .encoderType = null
    }
}

// Initialize predefined encoders
#init
{
    Writer.registerEncoder'(Y4m.Encoder)()
    Writer.registerEncoder'(Avi.Encoder)()
}
