#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Ogl

// An overflowing destination size is rejected before a strided copy reaches memory.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var renderer: RenderOgl
    renderer.setOffscreen()
    let gpu: IRenderer = &renderer
    var context        = expect gpu.createContext(null, 2, 2)
    defer gpu.deleteContext(&context)
    gpu.begin(context)
    gpu.init()

    var target = gpu.createRenderTarget(2, 2)
    defer gpu.deleteRenderTarget(&target)
    var readback: RenderOglReadback
    defer readback.release()
    Swag.require(readback.submit(&target, 0, 0, 1, 2))

    var destination: Array'u8
    destination.resize(4)
    for index in 4 do
        destination[index] = 0xA5
    let copied = readback.tryCopyTo(destination.toSlice(), rowStride: Swag.U64.Max - 3)
    Swag.require(not copied and readback.hasFailed())
    for byte in destination do
        Swag.require(byte == 0xA5)

    readback.release()
    Swag.require(readback.submit(&target, 0, 0, 1, 2))
    let undersized = readback.tryCopyTo(destination.toSlice(), rowStride: 4)
    Swag.require(not undersized and readback.hasFailed())
    for byte in destination do
        Swag.require(byte == 0xA5)

    readback.release()
    gpu.end()
}
