#global public

using Pixel

// Represents image list.
struct ImageList
{
    texture:     Texture // Texture associated with this value.
    totalFrames: s32 // Total frames associated with this value.
    frameSizeX:  s32 // Frame size x associated with this value.
    frameSizeY:  s32 // Frame size y associated with this value.
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
}
