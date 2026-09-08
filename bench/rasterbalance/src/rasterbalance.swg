using Core, Pixel

func recordScene(painter: *Painter, size: s32, region: u32)
{
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Black))
    painter.fillRect(0, 0, cast(f32) size, cast(f32) size, Color.fromArgb(Argb.White))
    let top    = region == 2 ? cast(f32) size * 0.75 : 0.0
    let height = region == 0 ? cast(f32) size : cast(f32) size * 0.25
    for layer in 16 do
        painter.fillRect(0, top, cast(f32) size, height, Color.fromArgb(64'u8, 210'u8, 60'u8, 30'u8))
    painter.end()
}

#[Swag.Safety(.Assert, true)]
func measure(name: string, size: s32, region: u32, expected: *Image)
{
    var cpu: RenderCpu
    cpu.begin(size, size)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var painter: Painter
    recordScene(&painter, size, region)

    for warmup in 4 do
        renderer.draw(&painter)
    for sample in 3
    {
        var watch: Time.Stopwatch
        watch.start()
        for repeat in 2 do
            renderer.draw(&painter)
        watch.stop()
        let result = cpu.surfaceImage()
        if Swag.workerCount() == 1 do
            expected[] = result
        else
        {
            Swag.assert(result.byteCount == expected.byteCount)
            for index in result.byteCount do
                Swag.assert(result.pixels[index] == expected.pixels[index])
        }

        Console.println(name, " size=", size, " workers=", Swag.workerCount(), " sample=", sample, " us=", watch.elapsedMicroseconds())
    }
}

#main
{
    var expected: [4] Image
    let workers:  [2] u32 = [1, 4]
    for count in workers
    {
        Swag.setWorkerCount(count)
        Swag.startWorkers()
        measure("small", 32, 0, &expected[0])
        measure("uniform", 512, 0, &expected[1])
        measure("heavy-head", 512, 1, &expected[2])
        measure("heavy-tail", 512, 2, &expected[3])
    }
}
