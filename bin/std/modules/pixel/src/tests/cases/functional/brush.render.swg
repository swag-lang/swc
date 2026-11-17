#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func renderBrushCpu(width, height: s32, painter: *Painter)->Image
{
    var renderer: RenderCpu
    renderer.begin(width, height)
    let render: IRenderer = &renderer
    expect render.draw(painter)
    render.end()
    return renderer.surfaceImage()
}

// A stop-free tinted gradient samples white and remains visible under normal alpha blending.
#test
{
    var brush = Brush.createLinearGradient(0, 0, 4, 0, Argb.Black, Argb.White)
    brush.gradientStops.clear()
    brush.setTint(Argb.Red)
    Swag.require(brush.hasVisibleAlpha())

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Argb.Zero)
    painter.fillRect({0, 0, 4, 4}, brush)
    painter.end()

    let image = renderBrushCpu(4, 4, &painter)
    Swag.require(image.pixelColor(1, 1) == Argb.Red)
}
