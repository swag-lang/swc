#global public

using Ogl, Core

// Describes a renderer-owned two-dimensional texture.
//
// The value does not own or release the graphics resource. Its handle is valid
// only for the renderer that created it.
struct Texture
{
    // What the renderer created. The four of them describe one resource, so they are established
    // together when the texture is created and never on their own: a width that disagrees with
    // the storage would silently corrupt every texture coordinate computed from it.
    readonly
    {
        handle: TextureHandle = InvalidTextureHandle     // Renderer-specific resource handle.
        pf:     PixelFormat   = undefined                // Pixel encoding of the texture storage.
        width:  s32           = 0                        // Width, in texels.
        height: s32           = 0                        // Height, in texels.
        valid:  bool          = false                    // Backend state flag retained for compatibility.
    }
}

// Selects how samples are interpolated between neighboring texels.
enum InterpolationMode
{
    Pixel      // Use nearest-neighbor sampling for hard pixel edges.
    Linear     // Blend neighboring texels for smooth scaling.
}

// Selects how source texture coordinates cover a destination shape.
enum UVMode
{
    Fill            // Stretch the complete texture over the destination.
    FillSubRect     // Stretch the configured texture sub-rectangle over the destination.
    Tile            // Repeat the texture over the destination.
}

impl Texture
{
    // Returns the tightly packed texture storage size, in bytes.
    mtd const getByteSize()->s32 => .width * .height * .pf.bpp() / 8

    // Reports whether the texture contains a non-invalid renderer handle.
    mtd const isValid()->bool => .handle != InvalidTextureHandle

    // Invalidates the descriptor without releasing a renderer resource.
    mtd clear()
    {
        .handle = InvalidTextureHandle
        .valid  = false
    }

    // Describes the resource a renderer just created.
    //
    // Only a renderer calls this: it is the one that knows the handle, and the geometry the
    // storage was really allocated with.
    internal mtd attach(handle: TextureHandle, pf: PixelFormat, width, height: s32)
    {
        .handle = handle
        .pf     = pf
        .width  = width
        .height = height
        .valid  = handle != InvalidTextureHandle
    }
}
