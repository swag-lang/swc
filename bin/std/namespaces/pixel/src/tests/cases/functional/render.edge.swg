#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A HiDPI spinner fan puts one side of its diagonal in a packed span and the
// other in a scalar tail. Captured device coordinates preserve that boundary.
#test
{
    const A        = Math.Vector2{198, 138}
    const B        = Math.Vector2{cast #bit (f32, 1128887668_u32), 138}
    const C        = Math.Vector2{cast #bit (f32, 1128821276_u32), cast #bit (f32, 1124889116_u32)}
    const D        = Math.Vector2{198, cast #bit (f32, 1124955508_u32)}
    const Source   = Color.fromArgb(128_u8, 255_u8, 0_u8, 0_u8)
    const Expected = Color.fromRgb(128, 0, 0)
    let brush          = Brush.createSolid(Source)
    let firstTriangle  = [A, B, C]
    let secondTriangle = [A, C, D]

    for fullMask in [false, true]
    {
        with var painter: Painter
        {
            .begin()
            .setColorMaskFull()
            .clear(Color.fromRgb(0, 0, 0))
            if not fullMask
            {
                .setColorMaskColor()
            }

            .setBlendingMode(.Alpha)
            .setAntialiased(false)
            .fillPolygon(firstTriangle, brush)
            .fillPolygon(secondTriangle, brush)
            .end()
        }

        let image = renderCpu(208, 152, &painter)
        Swag.require(image.pixelColor(198, 138) == Expected)
        Swag.require(image.pixelColor(199, 139) == Expected)
    }
}
