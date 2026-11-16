#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// A monitor nobody reported still has a usable scale: one, so a desktop that reports no monitor
// sizes its drawing as an unscaled one rather than as nothing.
#test
{
    var none: Env.Monitor
    Swag.require(none.scaleFactor == 1)
    Swag.require(Env.monitorForPoint(Math.Point{0, 0}).scaleFactor > 0)
}
