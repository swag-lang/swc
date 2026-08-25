//! Format: Image encoder registry.
//! Supported: Extension-selected registration and dispatch for every built-in and user-registered image encoder.
//! Not supported: This file does not write a concrete image format.
//! Role: This file owns format-neutral encoder registration and dispatch.
//
using Swag, Core, Core.Errors

// One registered encoder: the format it writes, and the type that writes it.
struct ImageEncoder
{
    format: ImageFormat
    type:   const *TypeInfoStruct
}

// Defines an encoder selected by filename extension.
public interface IImageEncoder
{
    // Describes the format this encoder writes.
    //
    // The registry stores the result once, at registration, and derives extension
    // matching from it. It is called on an encoder with no instance behind it, so it
    // must return a constant and must not read the encoder's own state.
    mtd format()->ImageFormat

    // Appends an encoded image to `buf`.
    //
    // `opt` is `null` for defaults or points to the encoder-specific options
    // structure. Fails for invalid images or unsupported dimensions/formats.
    mtd encode(buf: *ConcatBuffer, img: Image, opt: #null any) fail
}

public impl Image
{
    private var encoders: Array'ImageEncoder

    // Returns the registered encoder claiming `fileName`, or `null` when none does.
    private func getEncoder(fileName: string)->#null const *ImageEncoder
    {
        for &encoder in encoders where encoder.format.matches(fileName) do
            return encoder
        return null
    }

    // Registers an encoder type unless it is already present.
    func(T) registerEncoder()
    {
        #assert(Reflection.hasInterface(#typeof(T), IImageEncoder))

        for &encoder in encoders where encoder.type == #typeof(T) do
            return

        let itf = @mkinterface(null, #typeof(T), IImageEncoder)
        encoders.add({itf.format(), #typeof(T)})
    }

    // Returns the format written by each registered encoder, in registration order.
    //
    // The result is owned by the caller and is a snapshot: registering another encoder
    // afterwards does not change it. Use it to build the format list of a save dialog.
    func encodableFormats()->Array'ImageFormat
    {
        var result: retval
        result.reserve(encoders.count)
        for &encoder in encoders do
            result.add(encoder.format)
        return result
    }

    // Returns 'true' if the given filename has a corresponding encoder
    func canSave(fileName: string)->bool => getEncoder(fileName) != null

    // Encodes the image to an owned segmented memory buffer.
    //
    // `fileName` selects the encoder by extension; no file is opened.
    // Fails if the image is invalid or no encoder accepts the extension.
    mtd const encode(fileName: string, options: #null any = null)->ConcatBuffer fail
    {
        if !.pixels.buffer do
            fail InvalidFormatError{"invalid image"}

        let found = getEncoder(fileName)
        if !found do
            fail UnsupportedFormatError{"no matching image encoder"}
        let safeFound = found!

        // Create an encoder instance
        let ptrEncoder = Memory.new(safeFound.type)
        defer
        {
            if safeFound.type.opDrop do
                safeFound.type.opDrop(ptrEncoder)
            Memory.free(ptrEncoder, cast(u64) safeFound.type.sizeof)
        }

        // Encode
        // The registry only ever holds types that implement the interface, so the table resolves.
        let itf = @mkinterface(ptrEncoder, safeFound.type, IImageEncoder)!
        var result: retval
        itf.encode(&result, me, options)
        return result
    }

    // Encodes the image to one contiguous owned block.
    //
    // Selection works exactly as in [[Pixel.Image.encode]]. This is what a caller handing the
    // bytes to something that wants a single slice asks for — a clipboard medium, a drag payload,
    // a request body — rather than flattening the segmented buffer itself every time.
    mtd const encodeToBytes(fileName: string, options: #null any = null)->Array'u8 fail
    {
        var buffer = try .encode(fileName, options)
        buffer.makeLinear()

        var result: retval
        result.add(buffer.toSlice()!)
        return result
    }

    // Encodes the image and writes it to `fileName`.
    mtd const save(fileName: string, options: #null any = null) fail
    {
        var result = try .encode(fileName, options)
        File.writeAllBytes(fileName, result)
    }
}

// Initialize predefined encoders
#init
{
    Image.registerEncoder'(Bmp.Encoder)()
    Image.registerEncoder'(Tga.Encoder)()
    Image.registerEncoder'(Jpg.Encoder)()
    Image.registerEncoder'(Png.Encoder)()
    Image.registerEncoder'(Gif.Encoder)()
    Image.registerEncoder'(Tiff.Encoder)()
    Image.registerEncoder'(Ico.Encoder)()
    Image.registerEncoder'(Webp.Encoder)()
}
