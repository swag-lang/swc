#global public

using Pixel

// Represents icon.
struct Icon
{
    imageList: #null *ImageList // Image list associated with this value.
    index:     s32 // Index associated with this value.
    sizeX:     f32 = 24 // Size x associated with this value.
    sizeY:     f32 = 24 // Size y associated with this value.
    color:     Color // Color associated with this value.
}

impl Icon
{
    // Returns whether valid.
    #[Swag.Inline]
    mtd const isValid() => .imageList != null

    // Set icon to invalid
    mtd clear()
    {
        .imageList = null
    }

    // Initialize the icon from an image list
    func from(imageList: *ImageList, index: s32, sizeX, sizeY: f32 = 0)->Icon
    {
        var result: retval
        let sx = sizeX != 0 ? sizeX : cast(f32) imageList.frameSizeX
        let sy = sizeY != 0 ? sizeY : cast(f32) imageList.frameSizeY
        result.set(imageList, index, sx, sy)
        return result
    }

    // Initialize the icon from an image list
    mtd set(imageList: #null *ImageList, index: s32, sizeX, sizeY: f32 = 0)
    {
        .imageList = imageList
        .index     = index
        let sx = sizeX != 0 ? sizeX : cast(f32) (notnull imageList).frameSizeX
        let sy = sizeY != 0 ? sizeY : cast(f32) (notnull imageList).frameSizeY
        .sizeX = sx
        .sizeY = sy
    }

    // Paint icon at the given position
    mtd const paint(painter: *Painter, x, y: f32, color: Color = Argb.White)
    {
        if !.imageList or !.imageList.totalFrames do
            return

        let idx  = .index % .imageList.totalFrames
        var srcX = idx % .imageList.countX()
        var srcY = idx / .imageList.countX()

        srcX *= .imageList.frameSizeX
        srcY *= .imageList.frameSizeY

        let oldInterpol = painter.getInterpolationMode()
        if .sizeX == .imageList.frameSizeX and .sizeY == .imageList.frameSizeY do
            painter.setInterpolationMode(InterpolationMode.Pixel)
        else do
            painter.setInterpolationMode(InterpolationMode.Linear)
        defer painter.setInterpolationMode(oldInterpol)

        painter.drawTexture({x, y, .sizeX, .sizeY}, {srcX, srcY, .imageList.frameSizeX, .imageList.frameSizeY}, .imageList.texture, color)
    }
}
