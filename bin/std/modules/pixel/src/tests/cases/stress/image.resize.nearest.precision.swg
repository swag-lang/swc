#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#[Swag.TestTag("stress")]
#test
{
    const SourceWidth = 16_777_216
    var source = Image.create(SourceWidth, 1, .Gray8)
    source.pixels.storage()[SourceWidth - 2] = 17
    source.pixels.storage()[SourceWidth - 1] = 231

    let resized = source.resized(SourceWidth - 1, 1, .Nearest)
    Swag.require(resized.pixels.storage()[SourceWidth - 2] == 17)
}
