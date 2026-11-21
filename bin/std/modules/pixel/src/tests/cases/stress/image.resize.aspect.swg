#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Aspect-preserving resize must retain integer dimensions beyond f32's exact range.
#[Swag.TestTag("stress")]
#test
{
    let source = Image.create(16_777_217, 1, .Gray8)
    source.clear()
    let scaled = source.resized(0, 1)
    Swag.require(scaled.width == 16_777_217 and scaled.height == 1)
}
