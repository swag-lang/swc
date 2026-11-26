#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Shapes in separate spatial buckets still paint in document order across raster tiles.
#[Swag.TestTag("stress")]
#test
{
    var source = String.from("""\
        <svg viewBox='0 0 96 8192'><defs><clipPath id='left'>\
        <rect x='16' y='4070' width='16' height='48'/></clipPath></defs>""")
    for i in 8192 do
        source.appendFormat("<rect x='1' y='%' width='2' height='1'/>", (i * 2053) % 8192)

    source += """\
        <rect x='10' y='4078' width='60' height='24' fill='red'/>\
        <rect x='18' y='4086' width='32' height='26' fill='blue'/>\
        <rect x='18' y='4080' width='40' height='26' fill='lime' clip-path='url(#left)'/>\
        <rect x='78' y='4088' width='10' height='24' fill='yellow'/></svg>"""
    let drawing = expect Svg.Drawing.parse(source.toString())
    let image   = drawing.rasterize(96, 4200, 1)
    Swag.require(image.pixelColor(12, 4098) == Color.fromRgb(255, 0, 0))
    Swag.require(image.pixelColor(22, 4098) == Color.fromRgb(0, 255, 0))
    Swag.require(image.pixelColor(42, 4098) == Color.fromRgb(0, 0, 255))
    Swag.require(image.pixelColor(83, 4098) == Color.fromRgb(255, 255, 0))
}

// Overlaps crossing grid columns still use the authored order in a shifted viewport.
#[Swag.TestTag("stress")]
#test
{
    var source = String.from("""\
        <svg viewBox='0 0 8192 8192'><defs><clipPath id='small'>\
        <rect x='4092' y='4090' width='9' height='16'/></clipPath></defs>""")
    for i in 8192 do
        source.appendFormat("<rect x='%' y='%' width='2' height='1'/>", i * 4201 % 8192, i * 3343 % 8192)
    source += """\
        <rect x='4072' y='4072' width='62' height='48' fill='red'/>\
        <rect x='4068' y='4082' width='48' height='48' fill='blue'/>\
        <rect x='4090' y='4086' width='30' height='30' fill='lime' clip-path='url(#small)'/></svg>"""

    let drawing = expect Svg.Drawing.parse(source.toString())
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    cpu.begin(96, 96)
    defer renderer.end()
    var target = renderer.createRenderTarget(96, 96)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target, paintAlpha: false)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.pushClippingSurfaceRect({0, 0, 96, 96})
    drawing.paint(&painter, -4060, -4060)
    painter.popClippingRect()
    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)

    let image = renderer.readRenderTarget(&target, 0, 0, 96, 96)
    Swag.require((image.pixelColor(66, 45).argb & 0xFFFFFF) == 0xFF0000)
    Swag.require((image.pixelColor(48, 50).argb & 0xFFFFFF) == 0x0000FF)
    Swag.require((image.pixelColor(36, 38).argb & 0xFFFFFF) == 0x00FF00)
}
