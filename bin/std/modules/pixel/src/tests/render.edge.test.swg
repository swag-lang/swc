#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A HiDPI spinner fan puts one side of its diagonal in a packed span and the
// other in a scalar tail. Captured device coordinates preserve that boundary.
#test
{
    const A = Math.Vector2{198, 138}
    const B = Math.Vector2{cast #bit (f32, 1128887668'u32), 138}
    const C = Math.Vector2{cast #bit (f32, 1128821276'u32), cast #bit (f32, 1124889116'u32)}
    const D = Math.Vector2{198, cast #bit (f32, 1124955508'u32)}
    const Source = Color.fromArgb(128'u8, 255'u8, 0'u8, 0'u8)
    const Expected = Color.fromRgb(128, 0, 0)
    let brush = Brush.createSolid(Source)
    let firstTriangle = [A, B, C]
    let secondTriangle = [A, C, D]

    for fullMask in [false, true]
    {
        with var painter: Painter
        {
            .begin()
            .setColorMaskFull()
            .clear(Color.fromRgb(0, 0, 0))
            if not fullMask do
                .setColorMaskColor()
            .setBlendingMode(.Alpha)
            .setAntialiased(false)
            .fillPolygon(firstTriangle, brush)
            .fillPolygon(secondTriangle, brush)
            .end()
        }

        let image = renderCpu(208, 152, &painter)
        Swag.assert(image.pixelColor(198, 138) == Expected)
        Swag.assert(image.pixelColor(199, 139) == Expected)
    }
}
