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
    func getDecoder(fileName: string)->#null *ImageDecoder
    {
        for &decoder in decoders where decoder.format.matches(fileName) do
            return decoder
        return null
    }

    // Decode the given image buffer with the given decoder
    func decode(decoder: *ImageDecoder, bytes: const [..] u8, options: DecodeOptions = {})->Image fail
    {
        // Create a decoder instance
        let ptrDecoder = Memory.new(decoder.type)
        defer
        {
            if decoder.type.opDrop do
                decoder.type.opDrop(ptrDecoder)
            Memory.free(ptrDecoder, cast(u64) decoder.type.sizeof)
        }

        // Decode
        let itf = @mkinterface(ptrDecoder, decoder.type, IImageDecoder)
        return try itf.decode(bytes, options)
    }
}

// Load an image from file
public impl Image
{
    // Registers a decoder type unless it is already present.
    func(T) registerDecoder()
    {
        #assert(Reflection.hasInterface(#typeof(T), IImageDecoder))

        for &decoder in decoders where decoder.type == #typeof(T) do
            return

        let itf = @mkinterface(null, #typeof(T), IImageDecoder)
        decoders.add({itf.format(), #typeof(T)})
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
    func decode(fileName: string, bytes: #null const [..] u8, options: DecodeOptions = {})->Image fail
    {
        if !bytes do
            fail InvalidFormatError{"invalid image buffer"}
        let found = getDecoder(fileName)
        if !found do
            fail UnsupportedFormatError{"no matching image decoder"}
        return decode(cast(*ImageDecoder) (found), cast(const [..] u8) (bytes), options)
    }

    // Load the given image file
    func load(fileName: string, options: DecodeOptions = {})->Image fail
    {
        let found = getDecoder(fileName)
        if !found do
            fail UnsupportedFormatError{"no matching image decoder"}
        var bytes = File.readAllBytes(fileName)
        return decode(fileName, bytes.toSlice(), options)
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
        case "jpeg":                        extension = "jpg"
        case "x-icon", "vnd.microsoft.icon": extension = "ico"
        }

        let fileName = Format.toString("embedded.%", extension.toString())
        let bytes    = try Base64.decode(uri[marker + 8 to])
        return decode(fileName.toString(), bytes.toSlice(), options)
    }
}

// Initialize predefined decoders
#init
{
    Image.registerDecoder'(Bmp.Decoder)()
    Image.registerDecoder'(Tga.Decoder)()
    Image.registerDecoder'(Jpg.Decoder)()
    Image.registerDecoder'(Png.Decoder)()
    Image.registerDecoder'(Gif.Decoder)()
    Image.registerDecoder'(Tiff.Decoder)()
    Image.registerDecoder'(Ico.Decoder)()
    Image.registerDecoder'(Webp.Decoder)()
}
