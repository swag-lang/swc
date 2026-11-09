#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Swag, Core, Pixel

// Reports warmed-up frame acquisition on the active X11 server without image allocation.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var capture = expect X11Capture.create()
    let width  = Math.min(3840's32, cast(s32, capture.screen.width_in_pixels))
    let height = Math.min(2160's32, cast(s32, capture.screen.height_in_pixels))
    var source = expect ScreenFrameSource.create(false, 0, 0, width, height)
    var frame: Image
    expect source.grabInto(&frame)
    let storage = frame.pixels.storage()

    let iterations = width >= 3840 and height >= 2160 ? 16'u64 : 64'u64
    var watch: Time.Stopwatch
    watch.start()
    for iterations do
        expect source.grabInto(&frame)
    watch.stop()

    Swag.require(frame.pixels.storage() == storage)
    Swag.require(frame.pixels[3] == 255)
    Console.printf("X11 BGRA8 % by %: % us for % frames (% us/frame)\n",
                   width, height, watch.elapsedMicroseconds(), iterations,
                   watch.elapsedMicroseconds() / iterations)
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

// The optional MIT-SHM transfer and the ordinary GetImage path must produce
// identical bottom-up BGRA bytes at the active display resolution.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var capture = expect X11Capture.create()
    let width  = Math.min(3840's32, cast(s32, capture.screen.width_in_pixels))
    let height = Math.min(2160's32, cast(s32, capture.screen.height_in_pixels))
    var fallback = expect ScreenFrameSource.create(false, 0, 0, width, height)
    fallback.capture.shmDisabled = true
    var shared = expect ScreenFrameSource.create(false, 0, 0, width, height)
    var expected: Image
    var actual: Image
    expect fallback.grabInto(&expected)
    expect shared.grabInto(&actual)
    Swag.require(expected.byteCount == actual.byteCount)
    Swag.require(Memory.compare(expected.pixels.storage(), actual.pixels.storage(), expected.byteCount) == 0)
    Console.printf("X11 MIT-SHM % by %: %\n", width, height, shared.capture.shmData != null ? "enabled" : "fallback")
}

// Replacing a segment for a larger capture keeps the connection usable.
#[Swag.TestTag("integration.capture.x11")]
#test
{
    var capture = expect X11Capture.create()
    var frame: Image
    expect capture.imageInto(&frame, false, 0, 0, 32, 16)
    let firstSize = capture.shmSize
    expect capture.imageInto(&frame, false, 0, 0, 64, 32)
    Swag.require(frame.width == 64 and frame.height == 32)
    if capture.shmData do
        Swag.require(firstSize == 32 * 16 * 4 and capture.shmSize == 64 * 32 * 4)
}
