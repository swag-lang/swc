#global if #command == Swag.CompilerCommand.Test

using Core

// Pending fills own their contours, and their stencil coverage cuts subsequent commands.
#test
{
    var cpu: RenderCpu
    cpu.begin(32, 24)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var painter = Painter.createScanline(&cpu)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.White))
    painter.setColorMaskColor()
    painter.setClippingRect({4, 2, 22, 16})

    var contours: LinePathList
    contours.newPath().setRectRaw(6.25, 0, 18, 20)
    contours.newPath().setRect(10, 5, 5, 5)
    painter.startClippingRegion()
    painter.fillPath(&contours, Color.fromArgb(Argb.White), .EvenOdd)
    painter.endClippingRegion()
    contours.clear()

    contours.newPath().setRect(0, 0, 32, 24)
    painter.fillPath(&contours, Color.fromArgb(Argb.Black), .NonZero)
    contours.clear()
    painter.resetClippingRegion()
    painter.resetClippingRect()
    painter.fillRect({17, 5, 4, 4}, Color.fromArgb(Argb.Red))
    painter.end()
    expect renderer.draw(&painter)
    let image = cpu.surfaceImage()

    Swag.require(image.pixelColor(3, 7).argb == 0xFFFF_FFFF)
    Swag.require(image.pixelColor(8, 1).argb == 0xFFFF_FFFF)
    Swag.require(image.pixelColor(6, 7).argb == 0xFF40_4040)
    Swag.require(image.pixelColor(8, 7).argb == 0xFF00_0000)
    Swag.require(image.pixelColor(12, 7).argb == 0xFFFF_FFFF)
    Swag.require(image.pixelColor(18, 7).argb == 0xFFFF_0000)
    Swag.require(image.pixelColor(8, 18).argb == 0xFFFF_FFFF)
}

// A flat-ended stroke covers its fractional endpoints without a tessellation.
#test
{
    var cpu: RenderCpu
    cpu.begin(16, 10)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var painter = Painter.createScanline(&cpu)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.White))
    painter.setColorMaskColor()

    var path: LinePath
    path.start(3.25, 4.5)
    path.lineTo(12.75, 4.5)
    var pen = Pen.createSolid(Color.fromArgb(Argb.Black))
    pen.begCapStyle, pen.endCapStyle = .None
    painter.drawPath(&path, pen)
    painter.end()
    expect renderer.draw(&painter)
    let image = cpu.surfaceImage()

    Swag.require(image.pixelColor(2, 4).argb == 0xFFFF_FFFF)
    Swag.require(image.pixelColor(3, 4).argb == 0xFF40_4040)
    Swag.require(image.pixelColor(5, 4).argb == 0xFF00_0000)
    Swag.require(image.pixelColor(12, 4).argb == 0xFF40_4040)
    Swag.require(image.pixelColor(13, 4).argb == 0xFFFF_FFFF)
    Swag.require(image.pixelColor(5, 3).argb == 0xFFFF_FFFF)
}

// Clip coverage is the intersection of the actual sample spans at a shared pixel.
#test
{
    var cpu: RenderCpu
    cpu.begin(8, 8)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var painter = Painter.createScanline(&cpu)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.White))
    painter.setColorMaskColor()

    var a, b: LinePathList
    a.newPath().setRectRaw(1, 0, 0.75, 8)
    a.newPath().setRectRaw(3, 0, 0.25, 8)
    a.newPath().setRectRaw(4, 0, 3, 8)
    a.newPath().setRectRaw(5, 1, 1, 6)
    b.newPath().setRectRaw(1.5, 0, 0.5, 8)
    b.newPath().setRectRaw(3.5, 0, 0.25, 8)
    b.newPath().setRectRaw(4, 0, 3, 8)
    let recorded = painter.trySetClippingPathIntersection([ClippingPath{&a, .EvenOdd}, ClippingPath{&b, .NonZero}])
    Swag.require(recorded)
    a.clear()
    b.clear()
    a.newPath().setRectRaw(0, 0, 8, 8)
    painter.fillPath(&a, Color.fromArgb(Argb.Black), .NonZero)
    painter.end()
    expect renderer.draw(&painter)
    let image = cpu.surfaceImage()
    Swag.require(image.pixelColor(1, 4).argb == 0xFFBF_BFBF)
    Swag.require(image.pixelColor(3, 4).argb == 0xFFFF_FFFF)
    Swag.require(image.pixelColor(4, 4).argb == 0xFF00_0000)
    Swag.require(image.pixelColor(5, 4).argb == 0xFFFF_FFFF)
}

// Self-crossing strokes composite once and preserve the gaps in a rounded dash pattern.
#test
{
    var cpu: RenderCpu
    cpu.begin(30, 28)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var painter = Painter.createScanline(&cpu)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.White))
    painter.setColorMaskColor()

    var crossed: LinePath
    crossed.start(3, 6)
    crossed.lineTo(16, 6)
    crossed.lineTo(16, 15)
    crossed.lineTo(8, 15)
    crossed.lineTo(8, 3)
    var pen = Pen.createSolid(Color.fromArgb(0x8000_0000'u32), 4)
    pen.begCapStyle, pen.endCapStyle = .None
    painter.drawPath(&crossed, pen)

    var dashed: LinePath
    dashed.start(3, 21)
    dashed.lineTo(24, 21)
    pen = Pen.createSolid(Color.fromArgb(Argb.Black), 2)
    pen.begCapStyle, pen.endCapStyle = .None
    pen.dashStyle       = .Pattern
    pen.dashBegCapStyle = .Round
    pen.dashEndCapStyle = .Round
    pen.pattern.add(2)
    pen.pattern.add(2)
    painter.drawPath(&dashed, pen)

    painter.end()
    expect renderer.draw(&painter)
    let image = cpu.surfaceImage()
    Swag.require(image.pixelColor(5, 6).argb == 0xFF7F_7F7F)
    Swag.require(image.pixelColor(8, 6).argb == 0xFF7F_7F7F)
    Swag.require(image.pixelColor(16, 6).argb == 0xFF7F_7F7F)
    Swag.require(image.pixelColor(4, 21).argb == 0xFF00_0000)
    Swag.require(image.pixelColor(8, 21).argb == 0xFFFF_FFFF)
    Swag.require(image.pixelColor(12, 21).argb == 0xFF00_0000)
}

// A compound fill keeps fractional coverage when its contours span several clipped scan bands.
#test
{
    const Width  = 80
    const Height = 420
    let ink = Color.fromArgb(0x8020_6090'u32)
    var images: [2] Image
    for draw in 2
    {
        var cpu: RenderCpu
        cpu.begin(Width, Height)
        let renderer: IRenderer = &cpu
        defer renderer.end()
        var painter = Painter.createScanline(&cpu)
        painter.begin()
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.White))
        painter.setColorMaskColor()
        painter.setClippingRect({10, 5, 44, 406})
        painter.setTransform(Math.Transform2.createTranslation(0.25, 0.25))

        var contours: LinePathList
        for row in 104
        {
            for column in 12
            {
                contours.newPath().setRectRaw(cast(f32, 4 + column * 5), cast(f32, 2 + row * 4), 2.5, 2.5)
                if draw
                {
                    painter.fillPath(&contours, ink, .EvenOdd)
                    contours.clear()
                }
            }
        }

        if not draw do
            painter.fillPath(&contours, ink, .EvenOdd)
        painter.end()
        expect renderer.draw(&painter)
        images[draw] = cpu.surfaceImage()
    }

    Swag.require(images[0].pixelColor(10, 8).argb != 0xFFFF_FFFF)
    Swag.require(images[0].pixelColor(2, 8).argb == 0xFFFF_FFFF)
    for byte, index in images[0].pixels do
        Swag.require(byte == images[1].pixels[index])
}
