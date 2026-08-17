#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var painter: Painter

    @assert(painter.params().has(.Antialiased))

    painter.setAntialiased(false)
    @assert(!painter.params().has(.Antialiased))

    painter.setAntialiased()
    @assert(painter.params().has(.Antialiased))

    @assert(painter.interpolationMode() == .Pixel)
    painter.setInterpolationMode(.Linear)
    @assert(painter.interpolationMode() == .Linear)
}
