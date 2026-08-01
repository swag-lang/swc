#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var renderer: RenderOgl
    renderer.setupHeadless()

    var image: Image
    let texture = renderer.addImage(image)
    @assert(!texture.isValid())
    @assert(texture.width == 0 and texture.height == 0)
}
