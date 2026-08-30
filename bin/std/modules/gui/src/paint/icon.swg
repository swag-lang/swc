#global public

using Core, Pixel

// Describes one frame of an [[Gui.ImageList]] and its logical draw size.
//
// The image list remains owned by the caller and must outlive this borrowed descriptor.
struct Icon
{
    public
    {
        imageList: #null *ImageList     // Image list associated with this value.
        index:     s32                  // Index associated with this value.
        sizeX:     f32 = 24             // Size x associated with this value.
        sizeY:     f32 = 24             // Size y associated with this value.
        color:     Color                // Color associated with this value.
    }
}

impl Icon
{
    // Reports whether the icon refers to a valid atlas frame.
    #[Swag.Inline]
    mtd const isValid() => .imageList != null

    // Reports whether two descriptors name the same frame, drawn the same way.
    //
    // A caller that hands an icon over on every frame of a video or an animation needs this to
    // tell an actual change from a repetition, since the second must not cost a repaint.
    mtd const opEquals(other: Icon)->bool
    {
        return .imageList == other.imageList and
               .index == other.index and
               .sizeX == other.sizeX and
               .sizeY == other.sizeY and
               .color == other.color
    }

    // Restores an invalid icon with the default draw size.
    mtd clear()
    {
        Swag.init(me, 1)
    }

    // Creates a borrowed icon descriptor for one atlas frame.
    func from(imageList: *ImageList, index: s32, width = 0'f32, height = 0'f32)->Icon
    {
        var result: retval
        result.set(imageList, index, width, height)
        return result
    }

    // Replaces the referenced frame and logical draw size.
    mtd set(imageList: *ImageList, index: s32, width = 0'f32, height = 0'f32)
    {
        Debug.assert(imageList.isValid(), "image list is invalid")
        Debug.assert(index >= 0 and index < imageList.frameCount, "icon frame index is out of range")
        Debug.assert(width >= 0 and height >= 0, "icon size cannot be negative")

        .imageList = imageList
        .index     = index
        let sx = width != 0 ? width : cast(f32) imageList.frameWidth
        let sy = height != 0 ? height : cast(f32) imageList.frameHeight
        .sizeX = sx
        .sizeY = sy
    }

    // Paint icon at the given position
    mtd const paint(painter: *Painter, x, y: f32, color: Color = Argb.White)
    {
        if !.imageList or !.imageList.isValid() do
            return

        let idx  = .index
        var srcX = idx % .imageList.columnCount()
        var srcY = idx / .imageList.columnCount()

        srcX *= .imageList.frameWidth
        srcY *= .imageList.frameHeight

        let oldInterpol = painter.interpolationMode()
        if .sizeX == .imageList.frameWidth and .sizeY == .imageList.frameHeight do
            painter.setInterpolationMode(InterpolationMode.Pixel)
        else do
            painter.setInterpolationMode(InterpolationMode.Linear)
        defer painter.setInterpolationMode(oldInterpol)

        painter.drawTexture({x, y, .sizeX, .sizeY}, {srcX, srcY, .imageList.frameWidth, .imageList.frameHeight}, .imageList.texture, color)
    }
}
