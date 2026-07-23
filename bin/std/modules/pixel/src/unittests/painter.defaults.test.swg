#global #if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var painter: Painter

    @assert(painter.getParams().has(.Antialiased))

    painter.setAntialiased(false)
    @assert(!painter.getParams().has(.Antialiased))

    painter.setAntialiased()
    @assert(painter.getParams().has(.Antialiased))

    @assert(painter.getInterpolationMode() == .Pixel)
    painter.setInterpolationMode(.Linear)
    @assert(painter.getInterpolationMode() == .Linear)
}
