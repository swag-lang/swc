using Swag, Core, Core.Errors

struct ImageEncoder
{
    type:     const *TypeInfoStruct
    itf:      IImageEncoder
}

// Interface to decode a buffer
public interface IImageEncoder
{
    mtd canEncode(filename: string)->bool;
    mtd encode(buf: *ConcatBuffer, img: Image, opt: #null any) throw;
}

public impl Image
{
    fileprivate var encoders: Array'ImageEncoder

    // Register an image encoder
    func(T) addEncoder()
    {
        #assert(Reflection.hasInterface(#typeof(T), IImageEncoder))

        var encoder: ImageEncoder = undefined
        encoder.type = #typeof(T)
        encoder.itf  = @mkinterface(null, #typeof(T), IImageEncoder)
        encoders.add(encoder)
    }

    // Returns 'true' if the given filename has a corresponding encoder
    func canSave(fileName: string)->bool
    {
        foreach &encoder in encoders
        {
            if encoder.itf.canEncode(fileName) do
                return true
        }

        return false
    }

    // Save the image to a file.
    //
    // The body is delegated to the 'saveToFile' free function on purpose: the
    // 'encoders' registry is a static data member that is duplicated per module,
    // and only the copy in this (pixel) module is populated by the '#init' below.
    // An instance method like this one is materialized into the *calling* module,
    // where '&encoders' would resolve to that module's empty/uninitialized copy and
    // crash (access violation when called from another DLL/exe). A free function is
    // reached through this module's exported symbol, so it runs here and sees the
    // initialized registry.
    mtd save(fileName: string, options: any = null) throw
    {
        try saveToFile(me, fileName, options)
    }

    // Save 'image' to a file, picking the encoder from the file extension.
    func saveToFile(image: Image, fileName: string, options: any = null) throw
    {
        Debug.assert(image.pixels.buffer != null, "image is invalid")

        // Find the encoder that can treat 'fileName'
        var found: *ImageEncoder
        foreach &encoder in encoders
        {
            if encoder.itf.canEncode(fileName)
            {
                found = encoder
                break
            }
        }

        if !found do
            throw UnsupportedFormatError{"no matching image encoder"}

        // Create an encoder instance
        let ptrEncoder = Memory.new(found.type)
        defer
        {
            if found.type.opDrop do
                found.type.opDrop(ptrEncoder)
            Memory.free(ptrEncoder, cast(u64) found.type.sizeof)
        }

        // Encode
        let itf = @mkinterface(ptrEncoder, found.type, IImageEncoder)
        var result: ConcatBuffer
        itf.encode(&result, image, options)
        File.writeAllBytes(fileName, result)
    }
}

// Initialize predefined encoders
#init
{
    Image.addEncoder'(Bmp.Encoder)()
    Image.addEncoder'(Tga.Encoder)()
    Image.addEncoder'(Jpg.Encoder)()
    Image.addEncoder'(Png.Encoder)()
    Image.addEncoder'(Gif.Encoder)()
}
