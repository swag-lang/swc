using Core, Pixel

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 3)
    let count  = expect StrConv.toU32(args[2])
    let stroke    = args[1] == "strokes"
    let triangles = args[1] == "fills-triangles"
    Swag.require(stroke or triangles or args[1] == "fills")
    Swag.setWorkerCount(1)
    Swag.startWorkers()

    const Width = 1200
    const Height = 900
    let ink = Color.fromArgb(Argb.Black)
    for repetition in count + 1
    {
        let begin = Time.monotonicTicks()
        var cpu: RenderCpu
        cpu.begin(Width, Height)
        var renderer: IRenderer = &cpu
        defer renderer.end()
        var painter = Painter.createScanline(&cpu)
        painter.begin()
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.White))
        painter.setColorMaskColor()
        painter.setAntialiased(true)
        var pen = Pen.createSolid(ink, 2.25)
        pen.joinStyle   = .Round
        pen.begCapStyle = .None
        pen.endCapStyle = .None
        for i in 1200
        {
            let x = cast(f32, (i * 37) % 1056) + 0.25
            let y = cast(f32, (i * 19) % 820) + 36.625
            var paths: LinePathList
            let path = paths.newPath()
            path.start(x, y)
            for j in 1 to 7
            {
                let offset = cast(s32, (i * 5 + j * j * 9) % 43) - 21
                path.lineTo(x + cast(f32, j) * 16, y + cast(f32, offset))
            }

            if stroke do
                painter.drawPath(path, pen)
            else
            {
                path.lineTo(x + 112, y + 30)
                path.lineTo(x, y + 30)
                path.close()
                if triangles do
                    painter.fillPath(path, ink)
                else do
                    painter.fillPath(&paths, ink, .NonZero)
            }
        }

        painter.end()
        let recorded = Time.monotonicTicks()
        expect renderer.draw(&painter)
        let finished = Time.monotonicTicks()
        if repetition
        {
            let image = cpu.surfaceImage()
            var coverage = 0'u64
            for i in image.pixels.count / 4 do
                coverage += 255'u64 - image.pixels[i * 4]
            Console.println(Time.monotonicFrequency(), " ", recorded - begin, " ", finished - recorded, " ", coverage)
        }
    }
}
