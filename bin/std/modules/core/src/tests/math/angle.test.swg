#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    let direct = Math.Angle{rad: 1.25}
    @assert(direct.rad == 1.25)

    let halfTurn: Math.Angle = 180.0'deg
    @assert(Math.isEqualEpsilon(halfTurn.rad, Math.ConstF32.Pi, 0.001))
    @assert(Math.isEqualEpsilon(halfTurn.toDegrees(), 180.0, 0.001))

    let quarterTurn: Math.Angle = Math.ConstF32.PiBy2
    @assert(Math.isEqualEpsilon(quarterTurn.toDegrees(), 90.0, 0.001))

    let directLiteral: Math.Angle = 1.25'rad
    @assert(directLiteral.rad == 1.25)
}
