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
