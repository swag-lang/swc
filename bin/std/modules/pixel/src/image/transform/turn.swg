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
        var f = {img: me, angle: angle}
        dstImage.visitPixels(&f)
        {
            let data     = cast(*#decltype(f)) userData!
            let srcImage = cast(const *Image) data.img
            var nx, ny: s32
            switch data.angle
            {
            case .Clockwise90:
                nx = srcImage.width - y - 1
                ny = x

            case .HalfTurn:
                nx = srcImage.width - x - 1
                ny = srcImage.height - y - 1

            case .Clockwise270:
                nx = y
                ny = srcImage.height - x - 1
            }

            let pixSrc = srcImage.pixels.buffer! + cast(u64) nx * srcImage.bytesPerPixel + cast(u64) ny * srcImage.rowStride
            if srcImage.bytesPerPixel == 4 do
                pix[as u32] = pixSrc[as u32]
            elif srcImage.bytesPerPixel == 3
            {
                pix[0] = pixSrc[0]
                pix[1] = pixSrc[1]
                pix[2] = pixSrc[2]
            }
            else do
                Memory.copy(pix, pixSrc, srcImage.bytesPerPixel)
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
            result = create(.width, .height, .pixelFormat, alphaMode: me.alphaMode)
        else do
            result = create(.height, .width, .pixelFormat, alphaMode: me.alphaMode)
        .doTurn(&result, angle)
        return result
    }
}
