#global #[Swag.ExplicitNullability]
using Swag, Core

public enum PixelMode
{
    None
    Mono
    Gray
    Gray2
    Gray4
    Lcd
    LcdV
    Bgra
    Max
}

public struct Bitmap
{
    rows:             u32
    width:            u32
    pitch:            s32
    buffer:           #null [*] u8
    grayCount:        u16
    pixelMode:        PixelMode
}
