#global public

using Core, Core.Errors, Pixel

// One registered decoder: the format it reads, and the type that reads it.
internal struct DecoderDesc
{
    format: StreamFormat
    type:   const *Swag.TypeInfoStruct
}

// Decodes one video format, one frame at a time, from a byte source.
//
// A decoder instance is created per [[Video.Reader]] and keeps whatever state its format
// needs between frames. It never holds the stream: everything it reads comes from the
// [[Video.Source]] it is handed, so a decoder written this way costs the same memory on a
// ten-frame stream and on a ten-hour one.
//
// The two positioning operations are separate on purpose. `seekFrame` is where a format
// implements random access — a trivial multiplication for a fixed frame size, an index lookup
// for a container that carries one, a keyframe followed by decoding forward for an inter-coded
// format — while `decodeFrame` only ever decodes the frame the decoder is already positioned on.
interface IDecoder
{
    // Describes the format this decoder reads.
    //
    // The registry stores the result once, at registration, and derives extension matching
    // from it. It is called on a decoder with no instance behind it, so it must return a
    // constant and must not read the decoder's own state.
    mtd format()->StreamFormat

    // Reads the stream header, positions `source` on the first frame, and reports what the
    // stream contains.
    //
    // Fails when the stream is not in this decoder's format, is malformed, or uses features
    // the decoder does not support.
    mtd open(source: *Source)->StreamInfo fail

    // Positions the decoder so the next decoded frame is `index`.
    //
    // Repositioning to the frame the decoder is already on does nothing, which is what makes
    // ordered playback free of seeks.
    mtd seekFrame(source: *Source, index: u64) fail

    // Decodes the frame the decoder is positioned on into `target`, then advances to the next.
    //
    // `target` is reused when it already has the stream geometry and pixel format, and is
    // recreated otherwise, so a caller decoding a whole stream allocates one frame in total.
    mtd decodeFrame(source: *Source, target: *Image) fail
}

// Decodes the frames of a video stream without holding the stream in memory.
//
// A reader owns its source and its decoder instance. Frame `index` is zero-based; decoding
// frames in order never seeks, and decoding them out of order costs whatever random access
// costs in that format.
//
// The stream must remain available and unchanged while the reader is open: a file-backed
// reader keeps the file open, and a memory-backed reader borrows the bytes it was given.
#[Swag.NoCopy]
struct Reader
{
    internal
    {
        source:      Source                               // Bytes of the encoded stream.
        info:        StreamInfo                           // What the decoder reported when opening.
        format:      StreamFormat                         // Format claimed by the selected decoder.
        decoder:     #null IDecoder                       // Decoder instance owned by this reader.
        decoderType: #null const *Swag.TypeInfoStruct     // Concrete decoder type, used to release it.
    }
}

impl Reader
{
    internal var decoders: Array'DecoderDesc

    // Registers a decoder type unless it is already present.
    //
    // `T` must implement [[Video.IDecoder]]. Registration stores its format and its type;
    // instances are created on demand, one per open reader.
    func(T) registerDecoder()
    {
        #assert(Reflection.hasInterface(#typeof(T), IDecoder))

        registerDecoderImplementation(#typeof(T), @mkinterface(null, #typeof(T), IDecoder))
    }

    // Non-generic bridge used by registerDecoder after its body is instantiated in the caller's
    // module. The registry itself remains module-internal.
    #[Swag.NoDoc]
    func registerDecoderImplementation(type: const *Swag.TypeInfoStruct, itf: IDecoder)
    {
        for decoder in decoders where decoder.type == type do
            return
        decoders.add({itf.format(), type})
    }

    // Returns the format read by each registered decoder, in registration order.
    //
    // The result is owned by the caller and is a snapshot: registering another decoder
    // afterwards does not change it. Use it to build the format list of an open dialog.
    func decodableFormats()->Array'StreamFormat
    {
        var result: retval
        result.reserve(decoders.count)
        for decoder in decoders do
            result.add(decoder.format)
        return result
    }

    // Reports whether a registered decoder claims `fileName`, by its extension alone.
    func canOpen(fileName: string)->bool => findDecoder(fileName) != null

    // Returns the registered decoder claiming `fileName`, or `null` when none does.
    internal func findDecoder(fileName: string)->#null const *DecoderDesc
    {
        for decoder in decoders where decoder.format.matches(fileName) do
            return decoder
        return null
    }

    // Opens `fileName` and reads its stream header.
    //
    // The extension selects the decoder, and only the header is read: opening a stream costs
    // the same whatever its length. The file stays open until the reader is closed.
    //
    // ## Example
    //
    // ```swag
    // var reader = try Video.Reader.open("clip.avi")
    // var frame: Pixel.Image
    // for index in reader.frameCount() do
    //     try reader.decodeFrameInto(&frame, index)
    // ```
    func open(fileName: string)->Reader fail
    {
        var result: retval
        result.source = Source.openFile(fileName)
        result.start(fileName)
        return result
    }

    // Opens an encoded stream held in memory, without copying it.
    //
    // `fileName` selects the decoder by extension; no file is opened. `bytes` is borrowed and
    // must stay valid and unchanged until the reader is closed.
    func openMemory(fileName: string, bytes: const [..] u8)->Reader fail
    {
        var result: retval
        result.source = Source.openMemory(bytes)
        result.start(fileName)
        return result
    }

    // Selects the decoder for `fileName`, creates its instance, and opens the source with it.
    private mtd start(fileName: string) fail
    {
        let found = findDecoder(fileName)
        if !found do
            fail UnsupportedFormatError{"no video decoder accepts this file extension"}

        let selected = found!
        .format      = selected.format
        .decoderType = selected.type
        .decoder     = @mkinterface(Memory.new(selected.type), selected.type, IDecoder)
        .info        = .decoder.open(&.source)
    }

    // Releases the decoder instance and the source when the reader leaves scope.
    mtd opDrop()
    {
        .close()
    }

    // Closes the source and releases the decoder. Repeated calls do nothing.
    mtd close()
    {
        if .decoder
        {
            let type     = .decoderType!
            let instance = @dataof(.decoder)!
            if type.opDrop do
                type.opDrop(instance)
            Memory.free(instance, cast(u64) type.sizeof)
            .decoder     = null
            .decoderType = null
        }

        .source.close()
    }

    // Reports whether the reader still owns an open stream.
    mtd const isOpen()->bool => .decoder != null

    // Returns everything the decoder reported about the stream.
    mtd const streamInfo()->StreamInfo => .info

    // Returns the format of the opened stream.
    mtd const streamFormat()->StreamFormat => .format

    // Returns the file the reader streams, or an empty string for a memory stream.
    mtd const sourcePath()->string => .source.sourcePath()

    // Returns the frame width, in pixels.
    mtd const width()->s32 => .info.width

    // Returns the frame height, in pixels.
    mtd const height()->s32 => .info.height

    // Returns the exact frame rate.
    mtd const frameRate()->FrameRate => .info.frameRate

    // Returns the number of frames, or zero when the format cannot report it.
    mtd const frameCount()->u64 => .info.frameCount

    // Returns the stream duration in seconds, or zero when the frame count is unknown.
    mtd const durationInSeconds()->f64
    {
        if !.info.frameRate.isValid() do
            return 0
        return cast(f64) .info.frameCount * cast(f64) .info.frameRate.denominator() / cast(f64) .info.frameRate.numerator()
    }

    // Decodes frame `index` into an owned RGB8 image.
    //
    // `index` is zero-based. Prefer [[Video.Reader.decodeFrameInto]] when decoding more than
    // one frame: it reuses the pixel storage instead of allocating a frame every time.
    mtd decodeFrame(index: u64)->Image fail
    {
        var result: retval
        .decodeFrameInto(&result, index)
        return result
    }

    // Decodes frame `index` into `target`, reusing its pixel storage when it already matches
    // the stream geometry.
    //
    // Decoding frames in order never seeks and never rereads what it already read, so a player
    // costs one frame of memory and one frame of work per displayed frame, whatever the length
    // of the stream. Fails past the end of the stream, which is how the end of a stream with an
    // unknown frame count is reached.
    mtd decodeFrameInto(target: *Image, index: u64) fail
    {
        if !.decoder do
            fail BadParameterError{"video reader has no open stream"}
        if .info.frameCount and index >= .info.frameCount do
            fail BadParameterError{"video frame index exceeds the stream frame count"}

        .decoder.seekFrame(&.source, index)
        .decoder.decodeFrame(&.source, target)
    }
}

// Initialize predefined decoders
#init
{
    Reader.registerDecoder'(Y4m.Decoder)()
    Reader.registerDecoder'(Avi.Decoder)()
    Reader.registerDecoder'(Mp4.Decoder)()
}
