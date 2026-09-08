#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Small draws must not start a worker pool merely to decide to render serially.
#test
{
    let scheduler = Swag.schedulerInstance()
    let started   = scheduler.started.load()
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.fillRect({0, 0, 16, 16}, Color.fromArgb(Argb.White))
    painter.end()
    let image = renderCpu(16, 16, &painter)
    assertPixel(image, 8, 8, Argb.White)
    Swag.assert(scheduler.started.load() == started)
}

// Clipped draws with an offset first row and an incomplete final block keep the same coverage
// as a narrow serial target, including translucent overlaps across every block boundary.
#[Swag.TestTag("parallel")]
#test
{
    Swag.setWorkerCount(4)
    const Height = 531
    const Narrow = 8
    const Wide   = 1024
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Black))
    painter.fillRect(0, 7, 1024.0, 508.0, Color.fromArgb(128'u8, 255'u8, 0'u8, 0'u8))
    painter.fillRoundRect(0, 13, 960.0, 500.0, 24, 24, Color.fromArgb(128'u8, 0'u8, 255'u8, 0'u8))
    painter.fillRoundRect(0, 21, 900.0, 493.0, 40, 40, Color.fromArgb(96'u8, 0'u8, 0'u8, 255'u8))
    painter.end()

    let serial = renderCpu(Narrow, Height, &painter)
    for repeat in 3
    {
        let image = renderCpu(Wide, Height, &painter)
        for y in Height
        {
            for x in Narrow do
                Swag.assert(serial.pixelColor(x, y) == image.pixelColor(x, y))
        }
    }
}
