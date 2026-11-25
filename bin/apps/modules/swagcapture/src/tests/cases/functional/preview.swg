#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Capture previews retain the entire canvas, with a bounded resolution and no softening
// of pixels at their original size.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let capture = f.capture
    capture.width   = 956
    capture.height  = 189
    capture.backImg = Image.create(capture.width, capture.height, .BGRA8)
    capture.backImg.visitPixels()
    {
        cast(*u32, pix)[] = cast(u32, x < 100 ? Argb.Red : x >= 856 ? Argb.Blue : Argb.White)
    }
    capture.backgroundChanged()
    capture.computePreview()

    Swag.require(capture.preview.width == 768 and capture.preview.height == 151)
    Swag.require(capture.preview.pixelColor(20, 80).argb == Argb.Red)
    Swag.require(capture.preview.pixelColor(740, 80).argb == Argb.Blue)

    capture.width   = 24
    capture.height  = 12
    capture.backImg = Image.create(capture.width, capture.height, .BGRA8)
    capture.backImg.visitPixels()
    {
        cast(*u32, pix)[] = cast(u32, x < 12 ? Argb.Black : Argb.White)
    }
    capture.backgroundChanged()
    capture.computePreview()

    Swag.require(capture.preview.width == 24 and capture.preview.height == 12)
    Swag.require(capture.preview.pixelColor(11, 6).argb == Argb.Black)
    Swag.require(capture.preview.pixelColor(12, 6).argb == Argb.White)
}
