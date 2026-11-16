#global if #command == Swag.CompilerCommand.Test and (#os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux)
#global private

using Swag, Core

const HairlineWidth  = 176
const HairlineHeight = 112

// One-pixel rules the way a grid draws them: horizontal and vertical, each a tenth of a pixel
// further from the device grid than the one before, so the set crosses every place where a rule
// has to choose the row or the column it lands on.
func renderHairlines(renderer: IRenderer, antialiased: bool)->Image
{
    var target = renderer.createRenderTarget(HairlineWidth, HairlineHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(255'u8, 240'u8, 242'u8, 243'u8))
    painter.setBlendingMode(.Alpha)
    painter.setAntialiased(antialiased)

    let rule = Color.fromArgb(255'u8, 40'u8, 60'u8, 80'u8)
    for i in 11
    {
        let offset = cast(f32, i) * 0.1
        let y      = 6.0'f32 + cast(f32, i) * 9 + offset
        painter.drawLine(6, y, 80, y, rule)

        let x = 92.0'f32 + cast(f32, i) * 7 + offset
        painter.drawLine(x, 6, x, 104, rule)
    }

    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, HairlineWidth, HairlineHeight)
}

// A rule drawn without antialiasing lands on the same row or column on both renderers.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    func scene(renderer: IRenderer)->Image => renderHairlines(renderer, false)
    assertSceneParity(&scene, "hairline.parity.aliased", HairlineWidth, HairlineHeight)
}

// An antialiased rule spreads over the same two rows or columns, in the same shares.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    func scene(renderer: IRenderer)->Image => renderHairlines(renderer, true)
    assertSceneParity(&scene, "hairline.parity.antialiased", HairlineWidth, HairlineHeight)
}
