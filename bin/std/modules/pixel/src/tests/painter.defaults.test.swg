#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var painter: Painter

    Swag.assert(painter.params().has(.Antialiased))

    painter.setAntialiased(false)
    Swag.assert(!painter.params().has(.Antialiased))

    painter.setAntialiased()
    Swag.assert(painter.params().has(.Antialiased))

    Swag.assert(painter.interpolationMode() == .Pixel)
    painter.setInterpolationMode(.Linear)
    Swag.assert(painter.interpolationMode() == .Linear)
}
