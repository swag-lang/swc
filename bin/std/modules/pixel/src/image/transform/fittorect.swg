using Core

public impl Image
{
    // Resizes the image to fit inside the requested dimensions while preserving its aspect ratio.
    //
    // The result is the largest integer-sized image that fits inside the box; it is not padded to
    // the requested dimensions.
    mtd fitInside(width, height: s32, mode = ResizeMode.Bicubic)
    {
        Swag.assert(width > 0 and height > 0)
        let targetAspect = width / cast(f32, height)
        let imageAspect  = .aspectRatio()

        var newWidth, newHeight: s32
        if imageAspect > targetAspect
        {
            newWidth  = width
            newHeight = Math.max(1, cast(s32, Math.floor(newWidth / imageAspect)))
        }
        else
        {
            newHeight = height
            newWidth  = Math.max(1, cast(s32, Math.floor(newHeight * imageAspect)))
        }

        .resize(newWidth, newHeight, mode)
    }

    // Returns a copy resized to fit inside the requested dimensions, as by [[Pixel.Image.fitInside]].
    mtd const fittedInside(width, height: s32, mode = ResizeMode.Bicubic)->Image
    {
        var result: #returntype = me
        result.fitInside(width, height, mode)
        return result
    }

    // Resizes and center-crops the image to cover the requested dimensions.
    //
    // The aspect ratio is preserved during scaling. The result has exactly
    // `width` by `height` pixels.
    mtd cover(width, height: s32, mode = ResizeMode.Bicubic)
    {
        Swag.assert(width > 0 and height > 0)
        let targetAspect = width / cast(f32, height)
        let imageAspect  = .aspectRatio()

        var newWidth, newHeight: s32

        if imageAspect > targetAspect
        {
            newHeight = height
            newWidth  = cast(s32, Math.ceil(newHeight * imageAspect))
        }
        else
        {
            newWidth  = width
            newHeight = cast(s32, Math.ceil(newWidth / imageAspect))
        }

        .resize(newWidth, newHeight, mode)

        let cropX = (.width - width) / 2
        let cropY = (.height - height) / 2
        .crop(cropX, cropY, width, height)
    }

    // Returns a resized and center-cropped copy that covers the requested dimensions.
    mtd const covered(width, height: s32, mode = ResizeMode.Bicubic)->Image
    {
        var result: #returntype = me
        result.cover(width, height, mode)
        return result
    }
}
