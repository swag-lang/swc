#global public

using Pixel

// Describes a texture atlas split into equally sized animation or icon frames.
struct ImageList
{
    // The atlas and how it is cut into frames. `set` establishes all four together, so a frame
    // index always addresses a region the texture really has.

    public readonly
    {
        texture:     Texture     // Atlas holding every frame.
        frameCount:  s32         // Number of addressable frames in the atlas.
        frameWidth:  s32         // Width of one frame, in pixels.
        frameHeight: s32         // Height of one frame, in pixels.
    }
}

impl ImageList
{
    #[Swag.Inline]
    {
        // Returns the number of complete frame columns in the atlas.
        mtd const columnCount() => .texture.width / .frameWidth

        // Returns the number of complete frame rows in the atlas.
        mtd const rowCount() => .texture.height / .frameHeight

        // Reports whether the atlas and frame geometry are valid.
        mtd const isValid() => .texture.isValid() and .frameCount > 0
    }

    // Creates a frame atlas descriptor.
    //
    // Zero frame dimensions select the corresponding texture dimension. A zero
    // `frameCount` exposes every complete cell, in row-major order.
    func create(texture: Texture, frameWidth = 0, frameHeight = 0, frameCount = 0)->ImageList
    {
        var result: retval
        result.set(texture, frameWidth, frameHeight, frameCount)
        return result
    }

    // Replaces the atlas descriptor after validating its frame geometry.
    mtd set(texture: Texture, frameWidth = 0, frameHeight = 0, frameCount = 0)
    {
        Debug.assert(texture.isValid(), "texture is invalid")

        let resolvedWidth  = frameWidth != 0 ? frameWidth : texture.width
        let resolvedHeight = frameHeight != 0 ? frameHeight : texture.height
        Debug.assert(resolvedWidth > 0 and resolvedWidth <= texture.width, "invalid frame width")
        Debug.assert(resolvedHeight > 0 and resolvedHeight <= texture.height, "invalid frame height")

        let capacity      = (texture.width / resolvedWidth) * (texture.height / resolvedHeight)
        let resolvedCount = frameCount != 0 ? frameCount : capacity
        Debug.assert(resolvedCount > 0 and resolvedCount <= capacity, "invalid frame count")

        .texture     = texture
        .frameWidth  = resolvedWidth
        .frameHeight = resolvedHeight
        .frameCount  = resolvedCount
    }

    // Releases the atlas back to the renderer that created it, and empties the list.
    //
    // Call this before pointing the list at another atlas, or the previous texture leaks in the
    // renderer.
    mtd release(renderer: IRenderer)
    {
        if .texture.isValid() do
            renderer.removeTexture(&.texture)
        Swag.init(me, 1)
    }
}
