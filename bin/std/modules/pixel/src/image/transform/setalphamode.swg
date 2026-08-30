using Core

impl Image
{
    // Converts alpha association in place without changing the pixel format.
    //
    // Straight-to-premultiplied conversion multiplies RGB by alpha. The reverse divides RGB by
    // non-zero alpha and defines fully transparent pixels as black. Floating-point formats retain
    // values outside zero through one; normalized integer formats round to their stored precision.
    public mtd convertAlphaTo(newMode: AlphaMode)
    {
        Debug.assert(.isValid(), "image is invalid")
        Debug.assert(.pixelFormat.hasAlpha(), "alpha association requires an alpha channel")
        if newMode == .alphaMode do
            return

        var context = {image: me, oldMode: .alphaMode, newMode: newMode}
        Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
        {
            let params = cast(*#decltype(context)) data!
            let image  = cast(*Image) params.image
            let pixels = image.pixels.buffer! + cast(u64) row * image.rowStride
            for x in image.width
            {
                let pixel = pixels + cast(u64) x * image.bytesPerPixel
                writeLogicalPixelValue(pixel, image.pixelFormat, params.newMode, readLogicalPixelValue(pixel, image.pixelFormat, params.oldMode))
            }
        }

        .alphaMode = newMode
    }

    // Returns a copy with the requested alpha association.
    public mtd const convertedAlphaTo(newMode: AlphaMode)->Image
    {
        var result: retval = me
        result.convertAlphaTo(newMode)
        return result
    }
}
