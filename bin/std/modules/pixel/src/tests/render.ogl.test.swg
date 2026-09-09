#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var renderer: RenderOgl
    let render:   IRenderer = &renderer

    var image: Image
    let texture = render.addImage(image)
    Swag.assert(!texture.isValid())
    Swag.assert(texture.width == 0 and texture.height == 0)
}

// A shader travels to the driver as the bytes of its file, and GLSL accepts nothing at all
// before `#version`. An editor that writes a byte-order mark at the head of one would otherwise
// make every program built from it fail to compile, and a renderer left without its planar
// program draws a video as a black rectangle with nothing to say about it.
#test
{
    const Marked = [0xEF'u8, 0xBB, 0xBF, 0x23, 0x76, 0x65, 0x72]
    const Plain  = [0x23'u8, 0x76, 0x65, 0x72]
    const Mark   = [0xEF'u8, 0xBB]

    Swag.assert(RenderOgl.shaderSource(Marked) == "#ver")
    Swag.assert(RenderOgl.shaderSource(Plain) == "#ver")
    Swag.assert(RenderOgl.shaderSource(Mark).length == 2)
}
