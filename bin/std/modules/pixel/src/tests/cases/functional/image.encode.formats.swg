#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#[Serialization.Schema("pixel.image")]
struct MalformedImage
{
    #[Serialization.Key("pixels")]
    pixels: Array'u8

    #[Serialization.Key("metadata")]
    metadata: Array'ImageMetadata

    #[Serialization.Key("byteCount")]
    byteCount: u64
    width: s32
    height: s32

    #[Serialization.Key("rowStride")]
    rowStride: s32

    #[Serialization.Key("pixelFormat")]
    pixelFormat: PixelFormat

    #[Serialization.Key("alphaMode")]
    alphaMode: AlphaMode

    #[Serialization.Key("bitsPerPixel")]
    bitsPerPixel: u8

    #[Serialization.Key("bytesPerPixel")]
    bytesPerPixel: u8
}

func makeMalformedImage()->Image
{
    var malformed: MalformedImage
    malformed.pixels.add(1)
    malformed.pixels.add(2)
    malformed.pixels.add(3)
    malformed.pixels.add(4)
    malformed.byteCount = 4
    malformed.width = 2
    malformed.height = 1
    malformed.rowStride = 8
    malformed.pixelFormat = .RGBA8
    malformed.alphaMode = .Straight
    malformed.bitsPerPixel = 32
    malformed.bytesPerPixel = 4

    var buffer: ConcatBuffer
    var encoder: Serialization.Encoder'Serialization.Write.TagBin
    expect encoder.writeAll(&buffer, malformed)

    var decoder: Serialization.Decoder'Serialization.Read.TagBin
    return expect decoder.readAll'Image(buffer.toString().toSlice())
}

// Invalid image geometry is rejected before a format encoder reads the pixel buffer.
#test
{
    let image = makeMalformedImage()
    Swag.require(not image.isValid())

    var error: Swag.Error
    discard catch image.encode("image.bmp") as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// Type-erased encoder options are rejected before any typed cast.
#test
{
    let image = Image.create(2, 2, .RGBA8)
    let wrongOptions: any? = true

    var bmpErrorOutcome: Swag.Error
    discard catch image.encode("image.bmp", wrongOptions) as bmpErrorOutcome
    Swag.require(bmpErrorOutcome.value() != null)

    var pngErrorOutcome: Swag.Error
    discard catch image.encode("image.png", wrongOptions) as pngErrorOutcome
    Swag.require(pngErrorOutcome.value() != null)

    var jpgErrorOutcome: Swag.Error
    discard catch image.encode("image.jpg", wrongOptions) as jpgErrorOutcome
    Swag.require(jpgErrorOutcome.value() != null)

    var tgaErrorOutcome: Swag.Error
    discard catch image.encode("image.tga", wrongOptions) as tgaErrorOutcome
    Swag.require(tgaErrorOutcome.value() != null)

    var tiffErrorOutcome: Swag.Error
    discard catch image.encode("image.tiff", wrongOptions) as tiffErrorOutcome
    Swag.require(tiffErrorOutcome.value() != null)
}

// BMP and TGA only encode the four documented 8-bit RGB/BGR layouts.
#test
{
    let formats = [PixelFormat.Gray8, .GrayAlpha8, .Gray16, .GrayAlpha16, .GrayF16, .GrayAlphaF16, .GrayF32, .GrayAlphaF32, .RGB16, .RGBA16, .RGBF16, .RGBAF16, .RGBF32, .RGBAF32]
    for format in formats
    {
        var image = Image.create(3, 2, format)
        image.clear()
        var bmpErrorOutcome: Swag.Error
        discard catch image.encode("image.bmp") as bmpErrorOutcome
        let bmpError = bmpErrorOutcome.value()
        Swag.require(bmpError != null)
        var tgaErrorOutcome: Swag.Error
        discard catch image.encode("image.tga") as tgaErrorOutcome
        let tgaError = tgaErrorOutcome.value()
        Swag.require(tgaError != null)
        var rleErrorOutcome: Swag.Error
        discard catch image.encode("image.tga", Tga.EncodeOptions{rle: true}) as rleErrorOutcome
        let rleError = rleErrorOutcome.value()
        Swag.require(rleError != null)
    }
}
