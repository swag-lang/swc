#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var renderer: RenderOgl
    let render: IRenderer = &renderer

    var image: Image
    let texture = render.addImage(image)
    @assert(!texture.isValid())
    @assert(texture.width == 0 and texture.height == 0)
}
