#global public

using Ogl, Core

struct Texture
{
    handle: TextureHandle = InvalidTextureHandle
    pf:     PixelFormat = undefined
    width:  s32 = 0
    height: s32 = 0
    valid:  bool = false
}

enum InterpolationMode
{
    Pixel
    Linear
}

enum UVMode
{
    Fill
    FillSubRect
    Tile
}

impl Texture
{
    mtd const getByteSize()->s32 => .width * .height * .pf.bpp() / 8
    mtd const isValid()->bool    => .handle != InvalidTextureHandle

    mtd clear()
    {
        .handle = InvalidTextureHandle
    }
}
