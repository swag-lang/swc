#global public

using Pixel

// Represents image list.
struct ImageList
{
    // The atlas and how it is cut into frames. 'set' establishes all four together, so a frame
    // index always addresses a region the texture really has.
    readonly
    {
        texture:     Texture     // Atlas holding every frame.
        totalFrames: s32         // Number of frames the atlas is cut into.
        frameSizeX:  s32         // Width of one frame, in pixels.
        frameSizeY:  s32         // Height of one frame, in pixels.
    }
}

impl ImageList
{
    #[Swag.Inline]
    {
        // Performs the count x operation.
        mtd countX() => .texture.width / .frameSizeX

        // Performs the count y operation.
        mtd countY() => .texture.height / .frameSizeY
    }

    // Initialize image list
    mtd set(texture: Texture, fsx, fsy: s32 = 0, cpt: s32 = 0)
    {
        .texture     = texture
        .frameSizeX  = fsx != 0 ? fsx : texture.width
        .frameSizeY  = fsy != 0 ? fsy : texture.height
        .totalFrames = cpt != 0 ? cpt : (.texture.width / .frameSizeX) * (.texture.height / .frameSizeY)
    }

    // Releases the atlas back to the renderer that created it, and empties the list.
    //
    // Call this before pointing the list at another atlas, or the previous texture leaks in the
    // renderer.
    internal mtd releaseTexture(renderer: *RenderOgl)
    {
        if .texture.isValid() do
            renderer.removeTexture(&.texture)
        .texture     = {}
        .totalFrames = 0
        .frameSizeX  = 0
        .frameSizeY  = 0
    }
}
