#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Measures a warmed-up 1080p conversion without source creation or target allocation.
#[Swag.TestTag("stress")]
#test
{
    const Width      = 1920
    const Height     = 1080
    const Iterations = 64
    let image = Image.create(Width, Height, .BGRA8)
    Memory.set(image.pixels.storage(), 127, image.pixels.count)
    var frame: Nv12Frame
    expect frame.convertFrom(&image)
    Swag.require(frame.luma().count == Width * Height)
    Swag.require(frame.chroma().count == Width * Height / 2)
    Swag.require(frame.luma()[0] == 125 and frame.chroma()[0] == 128 and frame.chroma()[1] == 128)

    var watch: Time.Stopwatch
    watch.start()
    for Iterations do
        expect frame.convertFrom(&image)
    watch.stop()
    Console.printf("NV12 1080p BGRA8: % us for % frames (% us/frame)\n",
                   watch.elapsedMicroseconds(), Iterations, watch.elapsedMicroseconds() / Iterations)
}
