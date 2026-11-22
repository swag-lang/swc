#global if #command == Swag.CompilerCommand.Test

using Core

func renderDashPattern(pattern: const [..] f32, blankScale: f32 = 1)->Image
{
    var pen = Pen.createDash(.Pattern, Color.fromArgb(Argb.White), 6)
    pen.begCapStyle    = .None
    pen.endCapStyle    = .None
    pen.dashBlankScale = blankScale
    pen.pattern.resize(pattern.count)
    for index in pattern.count do
        pen.pattern[index] = pattern[index]

    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Black))
    painter.drawLine(8, 24, 152, 24, pen)
    painter.end()

    var renderer: RenderCpu
    renderer.begin(160, 48)
    let render: IRenderer = &renderer
    expect render.draw(&painter)
    render.end()
    return renderer.surfaceImage()
}

// Odd custom patterns repeat twice so each cycle keeps alternating visible and blank lengths.
#test
{
    let singleOdd  = renderDashPattern([1.0'f32])
    let singlePair = renderDashPattern([1.0'f32, 1.0'f32])
    Swag.require(Slice.equals(singleOdd.pixels.toSlice(), singlePair.pixels.toSlice()))

    let tripleOdd  = renderDashPattern([1.0'f32, 1.0'f32, 1.0'f32], blankScale: 2)
    let triplePair = renderDashPattern([1.0'f32, 1.0'f32, 1.0'f32,
                                        1.0'f32, 1.0'f32, 1.0'f32],
                                       blankScale: 2)
    Swag.require(Slice.equals(tripleOdd.pixels.toSlice(), triplePair.pixels.toSlice()))
}
