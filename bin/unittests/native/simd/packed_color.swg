#global private
using Swag

struct Color
{
    b, g, r, a: u8
    #[Offset("b")]
    argb: u32
}

#[NoInline]
func packedColor(color: Color)->u32
{
    let packed   = cast(#simd [4] u32, [color.argb, 0, 0, 0])
    let channels = Swag.vecWidenLo(Swag.vecWidenLo(cast #bit (#simd [16] u8, packed)))
    let words    = Swag.vecNarrowSatU(cast #bit (#simd [4] s32, channels), cast #bit (#simd [4] s32, channels))
    let bytes    = Swag.vecNarrowSatU(cast #bit (#simd [8] s16, words), cast #bit (#simd [8] s16, words))
    return cast #bit (#simd [4] u32, bytes)[0]
}

#test
{
    for argb in [0'u32, 0xFF0503FF'u32, 0x01FF8000'u32, 0xFFFFFFFF'u32]
    {
        var color: Color
        color.argb = argb
        Swag.assert(packedColor(color) == argb)
    }
}
