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
    var pen = Pen.createSolid(Color.fromArgb(0x8000_0000_u32), 4)
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

// A compound fill keeps fractional coverage for short contours and one contour crossing every band.
#test
{
    const Width  = 80
    const Height = 420
    let ink = Color.fromArgb(0x8020_6090_u32)
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
        contours.newPath().setRectRaw(22, 0, 1.5, Height)
        if draw
        {
            painter.fillPath(&contours, ink, .EvenOdd)
            contours.clear()
        }

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

        if not draw
        {
            painter.fillPath(&contours, ink, .EvenOdd)
        }

        painter.end()
        expect renderer.draw(&painter)
        images[draw] = cpu.surfaceImage()
    }

    Swag.require(images[0].pixelColor(10, 8).argb != 0xFFFF_FFFF)
    Swag.require(images[0].pixelColor(2, 8).argb == 0xFFFF_FFFF)
    Swag.require(images[0].pixelColor(22, 209).argb != 0xFFFF_FFFF)
    for byte, index in images[0].pixels
    {
        Swag.require(byte == images[1].pixels[index])
    }
}

// Clipping a scan band keeps the same fractional coverage as resolving a larger stencil.
#test
{
    const Width  = 194
    const Height = 430
    let white = Color.fromArgb(Argb.White)
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
        painter.clear(white)
        painter.setColorMaskColor()
        painter.setTransform(Math.Transform2.createTranslation(0.25, 0.25))

        var paths: LinePathList
        painter.startClippingRegion()
        if draw
        {
            // Two identical contours cancel without leaving coverage in the larger bounds.
            paths.newPath().setRectRaw(0, 0, Width, Height)
            paths.newPath().setRectRaw(0, 0, Width, Height)
            painter.fillPath(&paths, white, .EvenOdd)
            paths.clear()
        }

        paths.newPath().setRectRaw(27.25, 278.375, 31.5, 22.25)
        painter.fillPath(&paths, white, .NonZero)
        paths.clear()
        painter.setClippingRegionMode(.Clear)
        paths.newPath().setRectRaw(15.125, 287.25, 159.5, 5.5)
        painter.fillPath(&paths, white, .NonZero)
        paths.clear()
        painter.endClippingRegion()

        let background = paths.newPath()
        background.start(0.125, 4.375)
        background.lineTo(187.625, 18.125)
        background.lineTo(192.875, 426.625)
        background.lineTo(18.375, 402.875)
        background.close()
        painter.fillPath(&paths, Color.fromArgb(0xB028_4060_u32), .EvenOdd)
        paths.clear()
        paths.newPath().setRectRaw(49.125, 2.5, 105.75, 425.75)
        painter.fillPath(&paths, Color.fromArgb(0x8050_8030_u32), .NonZero)
        painter.end()
        expect renderer.draw(&painter)
        images[draw] = cpu.surfaceImage()
    }

    Swag.require(images[0].pixelColor(3, 280) == white)
    Swag.require(images[0].pixelColor(40, 280) != white)
    Swag.require(images[0].pixelColor(40, 289) == white)
    Swag.require(images[0].pixelColor(40, 370) == white)
    for byte, index in images[0].pixels
    {
        Swag.require(byte == images[1].pixels[index])
    }
}

// Skipping leading samples and clamping both clip boundaries preserves crossings and winding.
#test
{
    let contour: [6] Math.Vector2 = [{2.125, 1.375}, {3.625, 27.625}, {9.375, 45.125},
                                     {21.125, 41.625}, {26.375, 6.625}, {11.875, 4.625}]
    let transform = Math.Transform2.Identity
    const FirstRow = 19
    const Height   = 48
    var reference, clipped: ScanScratch
    let all     = reference.startRows(Height)
    let visible = clipped.startRows(Height)
    addScanContour(all, contour, &transform, 1, {}, true, 32)
    addScanContour(visible, contour, &transform, 1, {}, true, 14, 7, FirstRow)

    for &line, row in visible
    {
        if row < FirstRow * VerticalSamples
        {
            Swag.require(line.crossings.isEmpty())
            continue
        }

        let expected = &all[row].crossings
        Swag.require(line.crossings.count == expected.count)
        for crossing, index in line.crossings
        {
            Swag.require(crossing.x == Math.clamp(expected[index].x, 7, 14))
            Swag.require(crossing.winding == expected[index].winding)
        }
    }
}

// Separating translucent fills with transform commands gives the same pixels as grouped fills.
#[Swag.TestTag("parallel")]
#test
{
    const Width  = 144
    const Height = 256
    let workers = Swag.workerCount()
    Swag.setWorkerCount(4)
    defer Swag.setWorkerCount(workers)
    var images: [2] Image
    for serial in 2
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

        var paths: LinePathList
        for pass in 2
        {
            let transform = Math.Transform2.createTranslation(0.25 + cast(f32, pass), 0.375)
            painter.setTransform(transform)
            painter.setClippingRect({5, 11 + cast(f32, pass) * 3, 133, 231})
            let count = pass == 0 ? 128 : 384
            for index in count
            {
                let x     = cast(f32, 4 + (index * 13) % 96) + 0.125
                let y     = cast(f32, 6 + (index * 17) % 220) + 0.25
                let size  = cast(f32, 24 + index % 14)
                let color = Color.fromArgb(0x9000_0000 | (cast(u32, index * 173_387 + pass * 3_521) & 0x00FF_FFFF))
                paths.newPath().setRectRaw(x, y, size, size + 11.5)
                if serial
                {
                    painter.setTransform(transform)
                }

                painter.fillPath(&paths, color, .NonZero)
                paths.clear()
            }
        }

        painter.end()
        expect renderer.draw(&painter)
        images[serial] = cpu.surfaceImage()
    }

    Swag.require(images[0].pixelColor(35, 128).argb != 0xFFFF_FFFF)
    Swag.require(images[0].pixelColor(1, 128).argb == 0xFFFF_FFFF)
    for byte, index in images[0].pixels
    {
        Swag.require(byte == images[1].pixels[index])
    }
}
