using Core

impl Image
{
    mtd const doFlip(dstImage: *Image)
    {
        let mec = cast #unconst (*Image) me
        let f   = dstImage
        mec.visitPixels(f, stride: .width)
        {
            let dstImage = cast(*Image) userData
            let w8       = image.width * image.bytesPerPixel
            Memory.copy(dstImage.pixels.buffer + (image.height - y - 1) * w8, pix, cast(u64) w8)
        }
    }

    // Flips the image upside down, in place.
    public mtd flip()
    {
        Swag.assert(.pixels.buffer != null)
        .allocWorkingBuffer()
        .doFlip(.safeWorkingBuffer())
        .applyWorkingBuffer()
    }

    // Returns an upside-down copy of the image.
    public mtd const flipped()->Image
    {
        Swag.assert(.pixels.buffer != null)
        var result: retval = create(.width, .height, .pixelFormat, alphaMode: me.alphaMode)
        .doFlip(&result)
        return result
    }
}
