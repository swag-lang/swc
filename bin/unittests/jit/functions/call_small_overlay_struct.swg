#global private

struct OverlayColor
{
    b, g, r, a: u8

    #[Offset("b")]
    argb: u32
}

func ReadOverlayAlpha(col: OverlayColor)->u8
{
    return col.a
}

func MergeOverlay(lhs, rhs: OverlayColor)->OverlayColor
{
    var result: retval
    result.a = lhs.a
    result.r = rhs.r
    result.g = lhs.g
    result.b = rhs.b
    return result
}

#test
{
    var lhs: OverlayColor
    lhs.b = 10
    lhs.g = 20
    lhs.r = 30
    lhs.a = 40

    var rhs: OverlayColor
    rhs.b = 50
    rhs.g = 60
    rhs.r = 70
    rhs.a = 80

    Swag.assert(ReadOverlayAlpha(lhs) == 40)

    let merged = MergeOverlay(lhs, rhs)
    Swag.assert(merged.b == 50)
    Swag.assert(merged.g == 20)
    Swag.assert(merged.r == 70)
    Swag.assert(merged.a == 40)
    Swag.assert(merged.argb == 0x28461432)
}
