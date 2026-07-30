#global public

using Ogl, Core

// Describes a renderer-owned two-dimensional texture.
//
// The value does not own or release the graphics resource. Its handle is valid
// only for the renderer that created it.
struct Texture
{
    handle: TextureHandle = InvalidTextureHandle     // Renderer-specific resource handle.
    pf:     PixelFormat   = undefined                // Pixel encoding of the texture storage.
    width:  s32           = 0                        // Width, in texels.
    height: s32           = 0                        // Height, in texels.
    valid:  bool          = false                    // Backend state flag retained for compatibility.
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
    }
}
