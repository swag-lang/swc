#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Converts a full-resolution BGRA frame and checks its NV12 planes.
#[Swag.TestTag("stress")]
#test
{
    const Width  = 1920
    const Height = 1080
    let image = Image.create(Width, Height, .BGRA8)
    Memory.set(image.pixels.storage(), 127, image.pixels.count)
    var frame: Nv12Frame
    expect frame.convertFrom(&image)
    Swag.require(frame.luma().count == Width * Height)
    Swag.require(frame.chroma().count == Width * Height / 2)
    Swag.require(frame.luma()[0] == 125 and frame.chroma()[0] == 128 and frame.chroma()[1] == 128)
}
