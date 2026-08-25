//! Format: Format-neutral video decoder registry and reader.
//! Supported: Extension-based decoder selection, streamed frame decoding, metadata, seeking, and optional audio packets.
//! Not supported: This file does not parse a concrete video or container format.
//! Role: This file owns decoder registration and the public reader that delegates to concrete format subfolders.
//
#global public

using Core, Core.Errors, Pixel, Audio

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

    // Returns the first frame at or after `index` that decodes without any earlier frame.
    //
    // In an intra-only format that is `index` itself; in an inter-coded one it is the next
    // sync sample. Returns the frame count when no such frame remains, so a caller that must
    // drop work — a player hopelessly behind its clock — can jump to the result and pay for
    // one decoded frame instead of every frame in between.
    mtd syncFrameAt(index: u64)->u64
}

// Internal capability for a container whose sample index is built on first decode.
#[Swag.NoDoc]
interface IDeferredDecoder
{
    mtd frameCount()->u64
    mtd frameRate()->FrameRate
    mtd durationInSeconds()->f64
    mtd requestCancel()
}

// Optional decoder capability exposing sound tracks carried by a video container.
interface IAudioDecoder
{
    // Returns the number of playable sound tracks.
    mtd audioTrackCount()->u32

    // Returns a sound track owned by the decoder, or `null` past the end.
    mtd audioTrack(index: u32)->#null const *SoundFile
}

// Optional decoder capability handing pictures over without converting them to RGB.
//
// A codec that reconstructs planar 4:2:0 implements this so a consumer drawing through a
// renderer never pays for a conversion on the processor: at 4K that conversion costs more than
// the entropy decode, the reconstruction and the loop filter together.
interface IPlanarDecoder
{
    // Reports whether the open stream decodes to planar pictures.
    //
    // A container carries more than one codec, so the capability is answered per stream and not
    // per decoder: an ISO-BMFF reader implements this and still says no for a Motion JPEG track.
    mtd hasPlanarFrames()->bool

    // Decodes the frame the decoder is positioned on into `target`, then advances to the next.
    //
    // Answers the same picture [[Video.IDecoder.decodeFrame]] would, in the codec's own layout.
    mtd decodeFramePlanes(source: *Source, target: *PlanarFrame) fail
}

// Optional decoder capability exposing exact presentation timestamps.
interface ITimedDecoder
{
    // Returns the presentation time of frame `index`, in seconds.
    mtd frameTimestamp(index: u64)->f64

    // Returns the frame presented at `seconds`, or the frame count past the end.
    mtd frameAtTime(seconds: f64)->u64
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
        source:        Source                               // Bytes of the encoded stream.
        info:          StreamInfo                           // What the decoder reported when opening.
        format:        StreamFormat                         // Format claimed by the selected decoder.
        decoder:       #null IDecoder                       // Decoder instance owned by this reader.
        audioDecoder:  #null IAudioDecoder                  // Optional sound-track capability.
        planarDecoder: #null IPlanarDecoder                 // Optional unconverted-picture capability.
        timedDecoder:  #null ITimedDecoder                  // Optional exact-timestamp capability.
        deferred:      #null IDeferredDecoder               // Optional deferred sample-index capability.
        decoderType:   #null const *Swag.TypeInfoStruct     // Concrete decoder type, used to release it.
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

        // The registry only ever holds types that implement the interface, so the table resolves.
        .decoder = @mkinterface(Memory.new(selected.type), selected.type, IDecoder)!
        let instance = @dataof(.decoder)
        .audioDecoder  = @mkinterface(instance, selected.type, IAudioDecoder)
        .planarDecoder = @mkinterface(instance, selected.type, IPlanarDecoder)
        .timedDecoder  = @mkinterface(instance, selected.type, ITimedDecoder)
        .deferred      = @mkinterface(instance, selected.type, IDeferredDecoder)
        .info          = .decoder.open(&.source)
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
            .decoder       = null
            .audioDecoder  = null
            .planarDecoder = null
            .timedDecoder  = null
            .deferred      = null
            .decoderType   = null
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

    // Returns the width the frames are meant to be shown at, or the stored width.
    //
    // A stream whose samples are not square states a size to show its pictures at that is not
    // the size it stores them in. Draw a frame into a rectangle of this shape and the picture
    // has the geometry it was mastered with; use [[Video.Reader.width]] to size a buffer.
    mtd const displayWidth()->s32 => .info.displayWidth ? .info.displayWidth : .info.width

    // Returns the height the frames are meant to be shown at, or the stored height.
    mtd const displayHeight()->s32 => .info.displayHeight ? .info.displayHeight : .info.height

    // Returns the exact frame rate.
    mtd const frameRate()->FrameRate => .deferred ? .deferred!.frameRate() : .info.frameRate

    // Returns the number of frames, or zero when the format cannot report it.
    mtd const frameCount()->u64 => .deferred ? .deferred!.frameCount() : .info.frameCount

    // Requests cancellation of deferred container indexing.
    //
    // This operation is safe from another thread and does nothing when the decoder has no
    // deferred work. Cancellation is permanent for this reader: close it after the interrupted
    // operation has returned.
    mtd requestCancel()
    {
        if .deferred do
            .deferred!.requestCancel()
    }

    // Returns the number of decoded sound tracks carried by the opened stream.
    mtd const audioTrackCount()->u32 => .audioDecoder ? .audioDecoder!.audioTrackCount() : 0

    // Returns sound track `index`, owned by this reader, or `null` past the end.
    //
    // The track streams from its own file cursor and remains valid until the reader is closed.
    mtd const audioTrack(index: u32)->#null const *SoundFile
    {
        return .audioDecoder ? .audioDecoder!.audioTrack(index) : null
    }

    // Returns the exact presentation time of frame `index` in seconds.
    //
    // Formats without timestamp metadata fall back to their declared frame rate.
    mtd const frameTimestamp(index: u64)->f64
    {
        if .timedDecoder do
            return .timedDecoder!.frameTimestamp(index)
        let rate = .frameRate()
        return cast(f64) index * cast(f64) rate.denominator() / cast(f64) rate.numerator()
    }

    // Returns the picture presented at `seconds`, or the frame count past the end.
    mtd const frameAtTime(seconds: f64)->u64
    {
        if .timedDecoder do
            return .timedDecoder!.frameAtTime(seconds)
        if seconds < 0 do
            return 0
        let rate = .frameRate()
        return Math.min(cast(u64) (seconds * cast(f64) rate.numerator() / cast(f64) rate.denominator()), .frameCount())
    }

    // Reports whether this stream can be decoded without converting its pictures to RGB.
    //
    // See [[Video.Reader.decodeFramePlanesInto]] for what that is worth.
    mtd const hasPlanarFrames()->bool => .planarDecoder != null and .planarDecoder!.hasPlanarFrames()

    // Decodes frame `index` into `target` in the codec's own planar 4:2:0 layout.
    //
    // Converting a picture to packed RGB is, at high resolutions, the most expensive stage of
    // decoding it, and a consumer that draws through a renderer does not need it: hand the
    // result to [[Pixel.Painter.drawVideoFrame]] instead. `target` keeps its storage across
    // calls, so decoding a whole stream allocates one picture.
    //
    // Fails on a stream whose codec does not produce planar pictures; ask
    // [[Video.Reader.hasPlanarFrames]] first.
    mtd decodeFramePlanesInto(target: *PlanarFrame, index: u64) fail
    {
        if !.decoder do
            fail BadParameterError{"video reader has no open stream"}
        if !.planarDecoder do
            fail UnsupportedFormatError{"video stream does not decode to planar pictures"}
        let count = .frameCount()
        if count and index >= count do
            fail BadParameterError{"video frame index exceeds the stream frame count"}

        .decoder.seekFrame(&.source, index)
        .refreshDeferredInfo()
        .planarDecoder!.decodeFramePlanes(&.source, target)
    }

    // Returns the first frame at or after `index` that decodes without any earlier frame.
    //
    // See [[Video.IDecoder.syncFrameAt]]; the result is the frame count when none remains.
    mtd const syncFrameAt(index: u64)->u64
    {
        if !.decoder do
            return 0
        return .decoder.syncFrameAt(index)
    }

    // Returns the stream duration in seconds, or zero when the format cannot report it.
    mtd const durationInSeconds()->f64
    {
        if .deferred do
            return .deferred!.durationInSeconds()
        let rate = .frameRate()
        if !rate.isValid() do
            return 0
        return cast(f64) .frameCount() * cast(f64) rate.denominator() / cast(f64) rate.numerator()
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
        let count = .frameCount()
        if count and index >= count do
            fail BadParameterError{"video frame index exceeds the stream frame count"}

        .decoder.seekFrame(&.source, index)
        .refreshDeferredInfo()
        .decoder.decodeFrame(&.source, target)
    }

    private mtd refreshDeferredInfo()
    {
        if !.deferred do
            return
        .info.frameCount = .deferred!.frameCount()
        .info.frameRate  = .deferred!.frameRate()
    }
}

// Initialize predefined decoders
#init
{
    Reader.registerDecoder'(Y4m.Decoder)()
    Reader.registerDecoder'(Avi.Decoder)()
    Reader.registerDecoder'(Mp4.Decoder)()
    Reader.registerDecoder'(Matroska.Decoder)()
}
