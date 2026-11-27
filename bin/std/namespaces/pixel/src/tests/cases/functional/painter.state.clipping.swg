#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Restoring a state without a clip also disables the clip already emitted to the renderer.
#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Black))
    painter.pushState()
    painter.pushClippingRect({0, 0, 2, 2})
    painter.popState()
    Swag.require(not painter.hasClippingRect())
    painter.fillRect({0, 0, 8, 8}, Color.fromArgb(Argb.White))
    painter.end()

    var renderer: RenderCpu
    renderer.begin(8, 8)
    let render: IRenderer = &renderer
    expect render.draw(&painter)
    render.end()

    let image = renderer.surfaceImage()
    Swag.require(image.pixelColor(7, 7) == Color.fromArgb(Argb.White))
}
