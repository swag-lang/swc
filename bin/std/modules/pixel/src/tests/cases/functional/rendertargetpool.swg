#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Crossing a power-of-two boundary must not quadruple temporary image storage.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.begin({width: 16, height: 16})
    let target = renderer.acquireRenderTarget(1025, 513)
    Swag.require(target.colorBuffer.width >= 1025 and target.colorBuffer.width < 1089)
    Swag.require(target.colorBuffer.height >= 513 and target.colorBuffer.height < 577)
    renderer.releaseRenderTarget(target)
    let tiny = renderer.acquireRenderTarget(12, 7)
    Swag.require(tiny.colorBuffer.width == 16 and tiny.colorBuffer.height == 8)
    renderer.releaseRenderTarget(tiny)
    renderer.end()
}

// Keep a hot target between frames, then release it after a frame without a borrower.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.begin({width: 16, height: 16})
    let first  = renderer.acquireRenderTarget(65, 33)
    let handle = first.handle
    renderer.releaseRenderTarget(first)
    renderer.end()

    renderer.begin({width: 16, height: 16})
    let again = renderer.acquireRenderTarget(65, 33)
    Swag.require(again.handle == handle)
    renderer.releaseRenderTarget(again)
    renderer.end()

    renderer.begin({width: 16, height: 16})
    renderer.end()
    renderer.begin({width: 16, height: 16})
    let fresh = renderer.acquireRenderTarget(65, 33)
    Swag.require(fresh.handle != handle)
    renderer.releaseRenderTarget(fresh)
    renderer.end()
}
