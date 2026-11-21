#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A raw update replaces every plane of a planar texture, including rounded 4:2:0 edges.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var renderer: RenderOgl
    renderer.setOffscreen()
    let gpu: IRenderer = &renderer
    var context        = expect gpu.createContext(null, 8, 8)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()

    var unpackBuffer: GLuint
    glGenBuffers(1, &unpackBuffer)
    defer
    {
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
        glDeleteBuffers(1, &unpackBuffer)
    }

    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpackBuffer)
    glBufferData(GL_PIXEL_UNPACK_BUFFER, 4, null, GL_STREAM_DRAW)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 8)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 32)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 1)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 2)

    for shift in [1's32, 0]
    {
        let chromaWidth = shift == 1 ? 2 : 3
        let chromaSize  = cast(u64, chromaWidth) * cast(u64, chromaWidth)
        var initial: Array'u8
        initial.resize(9 + chromaSize * 2)
        for i in 9'u64 do
            initial[i] = 16
        for i in 9'u64 until initial.count do
            initial[i] = 128

        let planes = YuvPlanarView{
            luma: initial.storage(),
            chromaB: initial.storage() + 9,
            chromaR: initial.storage() + 9 + chromaSize,
            lumaStride: 3,
            chromaStride: cast(u64, chromaWidth),
            width: 3,
            height: 3,
            chromaShift: shift}
        var texture = gpu.addImage(&planes)
        defer gpu.removeTexture(&texture)

        var updated: Array'u8
        updated.resize(texture.byteCount())
        for i in 9'u64 do
            updated[i] = 235
        for i in 9'u64 until updated.count do
            updated[i] = 128
        Swag.require(gpu.updateTexture(texture, updated.storage()))

        var unpackBinding, alignment, rowLength, skipRows, skipPixels: GLint
        glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBinding)
        glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment)
        glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength)
        glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skipRows)
        glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skipPixels)
        Swag.require(unpackBinding == cast(GLint, unpackBuffer) and
                     alignment == 8 and
                     rowLength == 32 and
                     skipRows == 1 and
                     skipPixels == 2)

        var target = gpu.createRenderTarget(3, 3)
        defer gpu.deleteRenderTarget(&target)
        var painter = Painter.create(gpu)
        painter.begin()
        painter.bindRenderTarget(&target)
        painter.setColorMaskFull()
        painter.clear(Argb.Black)
        painter.setBlendingMode(.Copy)
        painter.drawTexture({0, 0, 3, 3}, texture)
        painter.unbindRenderTarget()
        painter.end()
        expect gpu.draw(&painter)

        let image = gpu.readRenderTarget(&target, 0, 0, 3, 3)
        for y in 3's32
        {
            for x in 3's32 do
                Swag.require(image.pixelColor(x, y).r >= 250)
        }
    }

    gpu.end()
}
