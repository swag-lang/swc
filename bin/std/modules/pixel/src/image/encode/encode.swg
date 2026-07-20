using Swag, Core, Core.Errors

struct ImageEncoder
{
    type:     #nonull const *TypeInfoStruct
    itf:      IImageEncoder
}

// Interface to decode a buffer
public interface IImageEncoder
{
    mtd canEncode(filename: #nonull string)->bool;
    mtd encode(buf: #nonull *ConcatBuffer, img: Image, opt: #null any) throw;
}

public impl Image
{
    private var encoders: Array'ImageEncoder

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
    func canSave(fileName: #nonull string)->bool
    {
        for &encoder in encoders
        {
            if encoder.itf.canEncode(fileName) do
                return true
        }

        return false
    }

    // Save the image to a file
    mtd save(fileName: #nonull string, options: #null any = null) throw
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
            throw UnsupportedFormatError{"no matching image encoder"}
        let safeFound = found orelse cast(#nonull *ImageEncoder) 1'u64

        // Create an encoder instance
        let ptrEncoder = Memory.new(safeFound.type)
        defer
        {
            if safeFound.type.opDrop do
                safeFound.type.opDrop(ptrEncoder)
            Memory.free(ptrEncoder, cast(u64) safeFound.type.sizeof)
        }

        // Encode
        let itf     = @mkinterface(ptrEncoder, safeFound.type, IImageEncoder)
        var result: ConcatBuffer
        itf.encode(&result, me, options)
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
    Image.addEncoder'(Tiff.Encoder)()
    Image.addEncoder'(Ico.Encoder)()
}
