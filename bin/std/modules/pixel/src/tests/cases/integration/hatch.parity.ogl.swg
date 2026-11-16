#global if #command == Swag.CompilerCommand.Test and (#os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux)
#global private

using Swag, Core

const HatchSceneWidth  = 180
const HatchSceneHeight = 84

const HatchStyles: [36] HatchStyle = [
    .Dot, .Horizontal, .HorizontalLight, .HorizontalNarrow, .Vertical, .VerticalLight,
    .VerticalNarrow, .SolidDiamond, .OutlinedDiamond, .HorizontalDark, .VerticalDark, .Grid,
    .GridLarge, .GridDotted, .Cross, .CrossLarge, .Percent5, .Percent10,
    .Percent20, .Percent25, .Percent30, .Percent40, .Percent50, .Percent60,
    .Percent70, .Percent75, .Percent80, .Percent90, .CheckBoard, .CheckBoardLarge,
    .Weave, .DiagonalForward, .DiagonalForwardLight, .DiagonalBackward, .DiagonalBackwardLight, .DiagonalCross]

// Every built-in hatch in its own cell. A pattern is authored from its top row down, and most
// of them are not their own mirror image: a renderer that stores them the other way up turns a
// forward diagonal into a backward one, which a symmetric pattern alone never shows.
func renderHatches(renderer: IRenderer)->Image
{
    var target = renderer.createRenderTarget(HatchSceneWidth, HatchSceneHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(255'u8, 30'u8, 32'u8, 38'u8))
    painter.setBlendingMode(.Alpha)

    for style, index in HatchStyles
    {
        let column = cast(f32, index % 9)
        let row    = cast(f32, index / 9)
        let cell   = Math.Rectangle{5 + column * 19, 3 + row * 20, 17, 18}
        painter.fillRect(cell, Brush.createHatch(style, Color.fromArgb(Argb.Gainsboro)))
    }

    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, HatchSceneWidth, HatchSceneHeight)
}

// A hatch reads the same way up on both renderers.
#[Swag.TestTag("integration.renderer.opengl")]
#test { assertSceneParity(&renderHatches, "hatch.parity", HatchSceneWidth, HatchSceneHeight) }
