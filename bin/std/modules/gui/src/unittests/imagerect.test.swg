#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

// An empty imagerect is a valid, hit-testable window.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 160)

    let img = ImageRect.create(&host.root, {20, 20, 120, 120})
    @assert(img != null)
    @assert(host.wndAt({40, 40}) == img)
    @assert(!img.movie.isValid())

    host.shutdown()
}
