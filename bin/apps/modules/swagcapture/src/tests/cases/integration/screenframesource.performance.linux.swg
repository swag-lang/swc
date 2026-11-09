#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Swag, Core, Pixel

// Reports warmed-up frame acquisition on the active X11 server without image allocation.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var capture = expect X11Capture.create()
    let width  = Math.min(1280's32, cast(s32, capture.screen.width_in_pixels))
    let height = Math.min(720's32, cast(s32, capture.screen.height_in_pixels))
    var source = expect ScreenFrameSource.create(false, 0, 0, width, height)
    var frame: Image
    expect source.grabInto(&frame)
    let storage = frame.pixels.storage()

    const Iterations = 64
    var watch: Time.Stopwatch
    watch.start()
    for Iterations do
        expect source.grabInto(&frame)
    watch.stop()

    Swag.require(frame.pixels.storage() == storage)
    Swag.require(frame.pixels[3] == 255)
    Console.printf("X11 BGRA8 % by %: % us for % frames (% us/frame)\n",
                   width, height, watch.elapsedMicroseconds(), Iterations,
                   watch.elapsedMicroseconds() / Iterations)
}

// Narrow captures exercise both a vector group and the scalar remainder of a row.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var reference = expect ScreenFrameSource.create(false, 0, 0, 8, 4)
    var wide: Image
    expect reference.grabInto(&wide)
    const Widths: [2] s32 = [2, 6]
    for width in Widths
    {
        var source = expect ScreenFrameSource.create(false, 0, 0, width, 4)
        var narrow: Image
        expect source.grabInto(&narrow)
        for y in 4
        {
            for x in width do
                Swag.require(narrow.pixelColor(x, y).argb == wide.pixelColor(x, y).argb)
        }
    }
}
