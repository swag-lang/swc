//! Format: Image decoder registry.
//! Supported: Extension-selected registration and dispatch for every built-in and user-registered image decoder.
//! Not supported: This file does not parse a concrete image format.
//! Role: This file owns format-neutral decoder registration and dispatch.
//
using Swag, Core, Core.Errors

// One registered decoder: the format it reads, and the type that reads it.
struct ImageDecoder
{
    format: ImageFormat
    type:   const *TypeInfoStruct
}

// Controls which parts of an encoded image are materialized.
public struct DecodeOptions
{
    public
    {
        decodePixels = true     // Decode pixel storage; disable for metadata and geometry probing.

        decodeMetadata = true     // Preserve supported format metadata in `Image.metadata`.

        maxFrames:       u32 = 65536         // Maximum number of images indexed by an image reader; zero removes the limit.
        maxPixels:       u64 = 134217728     // Maximum pixels in one decoded image or animation canvas; zero removes the limit.
        maxDecodedBytes: u64 = 536870912     // Maximum bytes in one decoded pixel buffer; zero removes the limit.
        maxInputBytes:   u64 = 536870912     // Maximum encoded bytes accepted by an image reader; zero removes the limit.
    }
}

impl DecodeOptions
{
    mtd const checkImage(width, height: s32, format: PixelFormat) fail
    {
        if width <= 0 or height <= 0 do
            fail InvalidFormatError{"image dimensions must be positive"}
        let pixels = cast(u64) width * cast(u64) height
        if .maxPixels and pixels > .maxPixels do
            fail UnsupportedFormatError{"image exceeds the decoded pixel limit"}
        let bytesPerPixel = format.bitsPerPixel() / 8
        if .maxDecodedBytes and bytesPerPixel and pixels > .maxDecodedBytes / bytesPerPixel do
            fail UnsupportedFormatError{"image exceeds the decoded byte limit"}
    }

    mtd const checkFrameCount(count: u64) fail
    {
        if count > 0x7FFFFFFF or (.maxFrames and count > .maxFrames) do
            fail UnsupportedFormatError{"image set exceeds the frame limit"}
    }
}

// Defines a decoder selected by filename extension and applied to encoded bytes.
public interface IImageDecoder
{
    // Describes the format this decoder reads.
    //
    // The registry stores the result once, at registration, and derives extension
    // matching from it. It is called on a decoder with no instance behind it, so it
    // must return a constant and must not read the decoder's own state.
    mtd format()->ImageFormat

    // Decodes one complete encoded buffer according to `opt`.
    //
    // Fails when the data is malformed, truncated, or uses unsupported features.
    mtd decode(buf: const [..] u8, opt: DecodeOptions)->Image fail
}

impl Image
{
    var decoders: Array'ImageDecoder

    // Find the decoder that can treat 'fileName'
    func getDecoder(fileName: string)->*ImageDecoder?
    {
        for &decoder in decoders where decoder.format.matches(fileName) do
            return decoder
        return null
    }

    // Decode the given image buffer with the given decoder
    func decode(decoderType: const *TypeInfoStruct, bytes: const [..] u8, options: DecodeOptions = {})->Image fail
    {
        if options.maxInputBytes and bytes.count > options.maxInputBytes do
            fail UnsupportedFormatError{"image exceeds the encoded byte limit"}
        if options.decodePixels and (options.maxPixels or options.maxDecodedBytes)
        {
            var probeOptions = options
            probeOptions.decodePixels   = false
            probeOptions.decodeMetadata = false
            let probe = decode(decoderType, bytes, probeOptions)
            options.checkImage(probe.width, probe.height, probe.pixelFormat)
        }

        // Create a decoder instance
        let ptrDecoder = Memory.new(decoderType)
        defer
        {
            if decoderType.opDrop do
                decoderType.opDrop(ptrDecoder)
            Memory.free(ptrDecoder, cast(u64) decoderType.sizeof)
        }

        // Decode
        // The registry only ever holds types that implement the interface, so the table resolves.
        let itf    = Swag.makeInterface(ptrDecoder, decoderType, IImageDecoder)!
        var result = #move try itf.decode(bytes, options)
        options.checkImage(result.width, result.height, result.pixelFormat)
        return #move result
    }
}

// Load an image from file
public impl Image
{
    // Registers a decoder type unless it is already present.
    func(T) registerDecoder()
    {
        #assert(Reflection.hasInterface(#typeof(T), IImageDecoder))
        registerDecoder(#typeof(T))
    }

    // Registers a decoder described by reflection, unless that type is already registered.
    //
    // `type` must implement [[Pixel.IImageDecoder]]. Its format method must return static
    // metadata without reading an instance. Registration updates the module's shared registry;
    // a decoding already in progress keeps using its selected type, including its metadata probe.
    func registerDecoder(type: const *TypeInfoStruct)
    {
        for &decoder in decoders where decoder.type == type do
            return

        let itf = Swag.makeInterface(null, type, IImageDecoder)!
        decoders.add({itf.format(), type})
    }

    // Returns the format read by each registered decoder, in registration order.
    //
    // The result is owned by the caller and is a snapshot: registering another decoder
    // afterwards does not change it. Use it to build the format list of an open dialog.
    func decodableFormats()->Array'ImageFormat
    {
        var result: retval
        result.reserve(decoders.count)
        for &decoder in decoders do
            result.add(decoder.format)
        return result
    }

    // Returns 'true' if the given filename has a corresponding decoder
    func canLoad(fileName: string)->bool => getDecoder(fileName) != null

    // Decode the given image buffer
    func decode(fileName: string, bytes: const [..] u8?, options: DecodeOptions = {})->Image fail
    {
        if !bytes do
            fail InvalidFormatError{"invalid image buffer"}
        let found = getDecoder(fileName)
        if !found do
            fail UnsupportedFormatError{"no matching image decoder"}

        // Both the metadata probe and decoding may register more codec types.
        return try decode(found.type, bytes!, options)
    }

    // Load the given image file
    func load(fileName: string, options: DecodeOptions = {})->Image fail
    {
        let found = getDecoder(fileName)
        if !found do
            fail UnsupportedFormatError{"no matching image decoder"}
        var file = File.MappedFile.open(fileName)
        if options.maxInputBytes and file.size() > options.maxInputBytes do
            fail UnsupportedFormatError{"image exceeds the encoded byte limit"}
        let region = file.mapAll()
        var result = #move try decode(fileName, region.bytes(), options)
        return #move result
    }

    // Decodes an image carried inline in a `data:` URI.
    //
    // This is how HTML and SVG documents embed a picture in their own source. Only the base64
    // form is read: `data:image/png;base64,...`. The media type selects the decoder the same way
    // a file extension does, and the payload is decoded with [[Core.Base64.decode]]. A reference
    // that is not an image data URI or names a media type with no decoder reports
    // `UnsupportedFormatError`; a malformed payload reports the codec's own failure.
    func fromDataUri(uri: string, options: DecodeOptions = {})->Image fail
    {
        if !Utf8.startsWith(uri, "data:image/") do
            fail UnsupportedFormatError{"not an image data URI"}

        let marker = Utf8.indexOf(uri, ";base64,")
        if marker == Swag.U64.Max do
            fail UnsupportedFormatError{"data URI images must use base64 encoding"}

        // The media type can carry parameters of its own; only its subtype names the format.
        var mediaType = uri[11 until marker]
        let semicolon = Utf8.indexOf(mediaType, ';'rune)
        if semicolon != Swag.U64.Max do
            mediaType = mediaType[0 until semicolon]

        var extension = String.from(mediaType).toLower()
        switch extension.toString()
        {
        case "jpeg": extension = "jpg"
        case "x-icon", "vnd.microsoft.icon": extension = "ico"
        }

        let fileName = #move Format.toString("embedded.%", extension.toString())
        let bytes    = #move try Base64.decode(uri[marker + 8 to])
        var result   = #move try decode(fileName.toString(), bytes.toSlice(), options)
        return #move result
    }
}

// Initialize predefined decoders
#init
{
    Image.registerDecoder'(Bmp.Decoder)()
    Image.registerDecoder'(Tga.Decoder)()
    Image.registerDecoder'(Jpg.Decoder)()
    Image.registerDecoder'(Png.Decoder)()
    Image.registerDecoder'(Gif.SetDecoder)()
    Image.registerDecoder'(Tiff.Decoder)()
    Image.registerDecoder'(Ico.Decoder)()
    Image.registerDecoder'(Webp.Decoder)()
    Image.registerDecoder'(Qoi.Decoder)()
    Image.registerDecoder'(Psd.Decoder)()
    Image.registerDecoder'(Dds.Decoder)()
    Image.registerDecoder'(Ktx2.Decoder)()
    Image.registerDecoder'(Exr.Decoder)()
}
