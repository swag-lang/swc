using Swag, Core, Core.Errors

struct ImageEncoder
{
    type: const *TypeInfoStruct
    itf:  IImageEncoder
}

// Defines an encoder selected by filename extension.
public interface IImageEncoder
{
    // Reports whether this encoder accepts the filename extension.
    mtd canEncode(filename: string)->bool

    // Appends an encoded image to `buf`.
    //
    // `opt` is `null` for defaults or points to the encoder-specific options
    // structure. Fails for invalid images or unsupported dimensions/formats.
    mtd encode(buf: *ConcatBuffer, img: Image, opt: #null any) fail
}

public impl Image
{
    private var encoders: Array'ImageEncoder

    // Registers an encoder type unless it is already present.
    func(T) registerEncoder()
    {
        #assert(Reflection.hasInterface(#typeof(T), IImageEncoder))

        for &encoder in encoders where encoder.type == #typeof(T) do
            return

        var encoder: ImageEncoder = undefined
        encoder.type = #typeof(T)
        encoder.itf  = @mkinterface(null, #typeof(T), IImageEncoder)
        encoders.add(encoder)
    }

    // Returns 'true' if the given filename has a corresponding encoder
    func canSave(fileName: string)->bool
    {
        for &encoder in encoders
        {
            if encoder.itf.canEncode(fileName) do
                return true
        }

        return false
    }

    // Encodes the image to an owned segmented memory buffer.
    //
    // `fileName` selects the encoder by extension; no file is opened.
    mtd const encode(fileName: string, options: #null any = null)->ConcatBuffer fail
    {
        Debug.assert(.pixels.buffer != null, "image is invalid")

        // Find the encoder that can treat 'fileName'
        var found: #null *ImageEncoder
        for &encoder in encoders
        {
            if encoder.itf.canEncode(fileName)
            {
                found = encoder
                break
            }
        }

        if !found do
            fail UnsupportedFormatError{"no matching image encoder"}
        let safeFound = notnull found

        // Create an encoder instance
        let ptrEncoder = Memory.new(safeFound.type)
        defer
        {
            if safeFound.type.opDrop do
                safeFound.type.opDrop(ptrEncoder)
            Memory.free(ptrEncoder, cast(u64) safeFound.type.sizeof)
        }

        // Encode
        let itf = @mkinterface(ptrEncoder, safeFound.type, IImageEncoder)
        var result: retval
        itf.encode(&result, me, options)
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
