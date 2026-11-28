#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var painter: Painter

    Swag.require(painter.params().has(.Antialiased))

    painter.setAntialiased(false)
    Swag.require(not painter.params().has(.Antialiased))

    painter.setAntialiased()
    Swag.require(painter.params().has(.Antialiased))

    Swag.require(painter.interpolationMode() == .Pixel)
    painter.setInterpolationMode(.Linear)
    Swag.require(painter.interpolationMode() == .Linear)
}
