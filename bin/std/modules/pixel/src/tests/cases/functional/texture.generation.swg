#global if #command == Swag.CompilerCommand.Test
#global private

// Moving a renderer to its next device generation retires its own textures only.
#test
{
    var onePixel, oddImage: Texture
    onePixel.attach(cast(TextureHandle, 1), .Yuv420, 1, 1)
    oddImage.attach(cast(TextureHandle, 2), .Yuv420, 3, 3)
    Swag.require(onePixel.byteCount() == 3)
    Swag.require(oddImage.byteCount() == 17)
}

#test
{
    var first = expect TextureGeneration.claim()
    defer first.release()
    var second = expect TextureGeneration.claim()
    defer second.release()
    Swag.require(first.isCurrent() and second.isCurrent())

    var texture, other, untracked: Texture
    texture.attach(cast(TextureHandle, 1), .RGBA8, 4, 4, first)
    other.attach(cast(TextureHandle, 1), .RGBA8, 4, 4, second)
    untracked.attach(cast(TextureHandle, 1), .RGBA8, 4, 4)

    first = first.next()
    Swag.require(not texture.isValid())
    Swag.require(other.isValid() and untracked.isValid())

    var replacement: Texture
    replacement.attach(cast(TextureHandle, 2), .RGBA8, 4, 4, first)
    Swag.require(replacement.isValid())
}

// Resetting a CPU renderer retires descriptors before their numeric handles are reused.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    var source              = Image.create(1, 1, .BGRA8)
    var oldImage            = renderer.addImage(source)
    var oldTarget           = renderer.createRenderTarget(1, 1)
    let oldTextureHandle    = oldImage.handle
    let oldTargetHandle     = oldTarget.handle
    let oldColorHandle      = oldTarget.colorBuffer.handle

    Swag.require(oldImage.isValid() and oldTarget.colorBuffer.isValid())
    cpu.reset()
    Swag.require(not oldImage.isValid() and not oldTarget.colorBuffer.isValid())

    var replacementImage  = renderer.addImage(source)
    var replacementTarget = renderer.createRenderTarget(1, 1)
    defer
    {
        renderer.removeTexture(&replacementImage)
        renderer.deleteRenderTarget(&replacementTarget)
    }

    Swag.require(replacementImage.handle == oldTextureHandle)
    Swag.require(replacementTarget.handle == oldTargetHandle)
    Swag.require(replacementTarget.colorBuffer.handle == oldColorHandle)

    renderer.removeTexture(&oldImage)
    renderer.deleteRenderTarget(&oldTarget)
    Swag.require(not oldImage.isValid() and oldImage.handle == InvalidTextureHandle)
    Swag.require(oldTarget.handle == InvalidRenderTargetHandle)
    Swag.require(replacementImage.isValid() and replacementTarget.colorBuffer.isValid())
    Swag.require(renderer.readTexturePixels(replacementImage, .BGRA8).count == 4)
    Swag.require(renderer.readRenderTarget(&replacementTarget, 0, 0, 1, 1).isValid())
}

// A painter recorded with a render target retired by reset fails before using a reused handle.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.begin({width: 2, height: 2})
    var oldTarget = renderer.acquireRenderTarget(1, 1)
    var painter   = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(oldTarget)
    painter.clear(Color.fromArgb(Argb.Red))
    painter.unbindRenderTarget()
    painter.releaseRenderTarget(oldTarget)
    painter.end()

    cpu.reset()
    renderer.begin({width: 2, height: 2})
    var replacement = renderer.acquireRenderTarget(1, 1)
    Swag.require(replacement.handle == oldTarget.handle)

    var errorOutcome: Swag.Error
    discard catch renderer.draw(&painter) as errorOutcome
    Swag.require(errorOutcome.value() is RenderResourceError)
    painter.begin()
    painter.end()
    expect renderer.draw(&painter)
    Swag.require(renderer.readRenderTarget(replacement, 0, 0, 1, 1).isValid())
    renderer.deleteRenderTarget(replacement)
}

// A retired backdrop capture target must not alias a new texture after CPU renderer reset.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.begin({width: 2, height: 2})
    var oldTarget = renderer.createRenderTarget(1, 1)
    var painter   = Painter.create(renderer)
    painter.begin()
    painter.captureBackdrop(oldTarget, {0, 0, 1, 1})
    painter.end()

    cpu.reset()
    renderer.begin({width: 2, height: 2})
    var replacement = renderer.createRenderTarget(1, 1)
    Swag.require(replacement.colorBuffer.handle == oldTarget.colorBuffer.handle)

    var errorOutcome: Swag.Error
    discard catch renderer.draw(&painter) as errorOutcome
    Swag.require(errorOutcome.value() is RenderResourceError)
    Swag.require(renderer.readRenderTarget(replacement, 0, 0, 1, 1).isValid())
}

// Releasing a target retired by reset destroys only its descriptor, never a reused target.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    var oldTarget = renderer.acquireRenderTarget(1, 1)
    var painter   = Painter.create(renderer)
    painter.begin()
    painter.releaseRenderTarget(oldTarget)
    painter.end()

    cpu.reset()
    var replacement = renderer.acquireRenderTarget(1, 1)
    Swag.require(replacement.handle == oldTarget.handle)
    expect renderer.draw(&painter)
    Swag.require(replacement.colorBuffer.isValid())
    Swag.require(renderer.readRenderTarget(replacement, 0, 0, 1, 1).isValid())
    renderer.deleteRenderTarget(replacement)
}

// Releasing a generation retires its textures, and a slot handed to another renderer revives none.
#test
{
    var generation = expect TextureGeneration.claim()
    var texture: Texture
    texture.attach(cast(TextureHandle, 1), .RGBA8, 4, 4, generation)
    generation.release()
    Swag.require(not texture.isValid())

    var reused = expect TextureGeneration.claim()
    defer reused.release()
    Swag.require(not texture.isValid())
}

// Exhaustion fails instead of creating resources that cannot be retired after device loss.
#test
{
    var generations: Array'TextureGeneration
    defer
    {
        for index in generations.count do
            generations[index].release()
    }

    for expectedCount in 1 until TextureGenerationSlots
    {
        generations.add(expect TextureGeneration.claim())
        Swag.require(generations.count == cast(u64, expectedCount))
    }

    Swag.require(generations.count == TextureGenerationSlots - 1)
    for generation in generations do
        Swag.require(generation.isCurrent())

    var exhausted: Swag.Error
    catch { discard try TextureGeneration.claim() } as exhausted
    Swag.require(exhausted.value() is RenderResourceError)

    let available = generations.count - 1
    generations[available].release()
    var replacement = expect TextureGeneration.claim()
    defer replacement.release()
    var texture: Texture
    texture.attach(cast(TextureHandle, 1), .RGBA8, 4, 4, replacement)
    replacement = replacement.next()
    Swag.require(not texture.isValid())
}
