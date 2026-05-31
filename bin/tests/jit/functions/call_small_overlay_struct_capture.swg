#global fileprivate
using Swag

struct OverlayColor
{
    b, g, r, a: u8

    #[Offset("b")]
    argb: u32
}

func BlendOverlay(col0, col1: OverlayColor, factor: f32)->OverlayColor
{
    func blendU8(v0, v1: u8, factor: f32)->u8
    {
        return cast(u8) (cast(f32) v0 + (cast(f32) v1 - v0) * factor)
    }

    var result: retval = undefined
    result.a = blendU8(col0.a, col1.a, factor)
    result.r = blendU8(col0.r, col1.r, factor)
    result.g = blendU8(col0.g, col1.g, factor)
    result.b = blendU8(col0.b, col1.b, factor)
    return result
}

func BlendOverlayGrid(topLeft, topRight, bottomLeft, bottomRight: OverlayColor)->OverlayColor
{
    let cb: func||()->OverlayColor = func|topLeft, topRight, bottomLeft, bottomRight|()->OverlayColor
    {
        let colH1 = BlendOverlay(topLeft, topRight, 0.25)
        let colH0 = BlendOverlay(bottomLeft, bottomRight, 0.25)
        return BlendOverlay(colH0, colH1, 0.5)
    }

    return cb()
}

func BlendOverlayGridMixin(topLeft, topRight, bottomLeft, bottomRight: OverlayColor)->OverlayColor
{
    #[Swag.Mixin]
    func run()->OverlayColor
    {
        let colH1 = BlendOverlay(topLeft, topRight, 0.25)
        let colH0 = BlendOverlay(bottomLeft, bottomRight, 0.25)
        return BlendOverlay(colH0, colH1, 0.5)
    }

    return run()
}

#[Swag.Macro]
func injectStmt(stmt: #code void)
{
    #inject(stmt)
}

func BlendOverlayInjected(topLeft, topRight: OverlayColor)->OverlayColor
{
    #[Swag.Mixin]
    func run()->OverlayColor
    {
        var result: OverlayColor
        injectStmt()
        {
            result = BlendOverlay(topLeft, topRight, 0.25)
        }
        return result
    }

    return run()
}

#test
{
    var topLeft: OverlayColor
    topLeft.a = 255
    topLeft.r = 10
    topLeft.g = 20
    topLeft.b = 30

    var topRight: OverlayColor
    topRight.a = 255
    topRight.r = 110
    topRight.g = 120
    topRight.b = 130

    var bottomLeft: OverlayColor
    bottomLeft.a = 255
    bottomLeft.r = 210
    bottomLeft.g = 220
    bottomLeft.b = 230

    var bottomRight: OverlayColor
    bottomRight.a = 255
    bottomRight.r = 250
    bottomRight.g = 240
    bottomRight.b = 230

    let result = BlendOverlayGrid(topLeft, topRight, bottomLeft, bottomRight)
    @assert(result.a == 255)
    @assert(result.r == 127)
    @assert(result.g == 135)
    @assert(result.b == 142)
    @assert(result.argb == 0xFF7F878E)

    let resultMixin = BlendOverlayGridMixin(topLeft, topRight, bottomLeft, bottomRight)
    @assert(resultMixin.a == 255)
    @assert(resultMixin.r == 127)
    @assert(resultMixin.g == 135)
    @assert(resultMixin.b == 142)
    @assert(resultMixin.argb == 0xFF7F878E)

    let injected = BlendOverlayInjected(topLeft, topRight)
    @assert(injected.a == 255)
    @assert(injected.r == 35)
    @assert(injected.g == 45)
    @assert(injected.b == 55)
    @assert(injected.argb == 0xFF232D37)
}
