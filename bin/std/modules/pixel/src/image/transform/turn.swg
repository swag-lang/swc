using Core

impl Image
{
    // Clockwise rotation applied by [[Image.rotate]] and [[Image.rotated]].
    public enum Rotation
    {
        Clockwise90      // Rotate clockwise by 90 degrees.
        HalfTurn         // Rotate by 180 degrees.
        Clockwise270     // Rotate clockwise by 270 degrees.
    }

    #[Swag.Safety(.All, false)]
    mtd const doTurn(dstImage: *Image, angle: Rotation)
    {
        #[Swag.Mixin]
        func(BPP: u8) doIt()
        {
            var f = {img: me}
            switch angle
            {
            case .Clockwise90:
                dstImage.visitPixels(&f)
                {
                    let data     = cast(*#decltype(f)) userData!
                    let srcImage = cast(const *Image) data.img
                    let nx       = srcImage.width - y - 1
                    let ny       = x
                    let pixSrc   = srcImage.pixels.buffer + (nx * srcImage.bytesPerPixel) + (ny * srcImage.rowStride)
                    copyPixelDirect'BPP(cast([*] u8) pix, cast([*] u8) pixSrc!)
                }

            case .HalfTurn:
                dstImage.visitPixels(&f)
                {
                    let data     = cast(*#decltype(f)) userData!
                    let srcImage = cast(const *Image) data.img
                    let nx       = srcImage.width - x - 1
                    let ny       = srcImage.height - y - 1
                    let pixSrc   = srcImage.pixels.buffer + (nx * srcImage.bytesPerPixel) + (ny * srcImage.rowStride)
                    copyPixelDirect'BPP(cast([*] u8) pix, cast([*] u8) pixSrc!)
                }

            case .Clockwise270:
                dstImage.visitPixels(&f)
                {
                    let data     = cast(*#decltype(f)) userData!
                    let srcImage = cast(const *Image) data.img
                    let nx       = y
                    let ny       = srcImage.height - x - 1
                    let pixSrc   = srcImage.pixels.buffer + (nx * srcImage.bytesPerPixel) + (ny * srcImage.rowStride)
                    copyPixelDirect'BPP(cast([*] u8) pix, cast([*] u8) pixSrc!)
                }
            }
        }

        switch .bitsPerPixel
        {
        case 24: doIt'24()
        case 32: doIt'32()
        default: Debug.assert(false)
        }
    }

    // Rotates the image clockwise by a predefined angle.
    public mtd rotate(angle: Rotation)
    {
        Debug.assert(.pixels.buffer != null)
        if angle == .HalfTurn do
            .allocWorkingBuffer()
        else do
            .allocWorkingBuffer(.height, .width, .pixelFormat)
        .doTurn(.safeWorkingBuffer(), angle)
        .applyWorkingBuffer()
    }

    // Returns a clockwise-rotated copy of the image.
    public mtd const rotated(angle: Rotation)->Image
    {
        Debug.assert(.pixels.buffer != null)

        var result: retval
        if angle == .HalfTurn do
            result = create(.width, .height, .pixelFormat)
        else do
            result = create(.height, .width, .pixelFormat)
        .doTurn(&result, angle)
        return result
    }
}
