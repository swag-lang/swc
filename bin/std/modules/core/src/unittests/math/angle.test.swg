#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#test
{
    let zero: Math.Angle = 0.0
    @assert(zero.rad == 0.0)
    @assert(zero.toDegrees() == 0.0)

    let zeroDeg: Math.Angle = 0.0'deg
    @assert(zeroDeg.rad == 0.0)
    @assert(zeroDeg.toDegrees() == 0.0)

    let zeroRad: Math.Angle = 0.0'rad
    @assert(zeroRad.rad == 0.0)
    @assert(zeroRad.toDegrees() == 0.0)

    let direct = Math.Angle{rad: 1.25}
    @assert(direct.rad == 1.25)
    @assert(Math.isEqualEpsilon(direct.toDegrees(), Math.toDegrees(1.25'f32), 0.001))

    let negativeDirect: Math.Angle = -Math.ConstF32.Pi
    @assert(Math.isEqualEpsilon(negativeDirect.rad, -Math.ConstF32.Pi, 0.001))
    @assert(Math.isEqualEpsilon(negativeDirect.toDegrees(), -180.0, 0.001))

    let quarterTurnDeg: Math.Angle = 90.0'deg
    @assert(Math.isEqualEpsilon(quarterTurnDeg.rad, Math.ConstF32.PiBy2, 0.001))
    @assert(Math.isEqualEpsilon(quarterTurnDeg.toDegrees(), 90.0, 0.001))

    let halfTurn: Math.Angle = 180.0'deg
    @assert(Math.isEqualEpsilon(halfTurn.rad, Math.ConstF32.Pi, 0.001))
    @assert(Math.isEqualEpsilon(halfTurn.toDegrees(), 180.0, 0.001))

    let fullTurn: Math.Angle = 360.0'deg
    @assert(Math.isEqualEpsilon(fullTurn.rad, Math.ConstF32.TwoPi, 0.001))
    @assert(Math.isEqualEpsilon(fullTurn.toDegrees(), 360.0, 0.001))

    let negativeQuarterTurn: Math.Angle = -90.0'deg
    @assert(Math.isEqualEpsilon(negativeQuarterTurn.rad, -Math.ConstF32.PiBy2, 0.001))
    @assert(Math.isEqualEpsilon(negativeQuarterTurn.toDegrees(), -90.0, 0.001))

    let quarterTurn: Math.Angle = Math.ConstF32.PiBy2
    @assert(Math.isEqualEpsilon(quarterTurn.toDegrees(), 90.0, 0.001))

    let directLiteral: Math.Angle = 1.25'rad
    @assert(directLiteral.rad == 1.25)
    @assert(Math.isEqualEpsilon(directLiteral.toDegrees(), Math.toDegrees(1.25'f32), 0.001))

    let negativeRadLiteral: Math.Angle = -1.25'rad
    @assert(negativeRadLiteral.rad == -1.25)
    @assert(Math.isEqualEpsilon(negativeRadLiteral.toDegrees(), Math.toDegrees(-1.25'f32), 0.001))
}

#test
{
    struct Holder
    {
        angle: Math.Angle
    }

    let positive = Holder{angle: 10.0'deg}
    @assert(Math.isEqualEpsilon(positive.angle.rad, Math.toRadians(10.0'f32), 0.001))
    @assert(Math.isEqualEpsilon(positive.angle.toDegrees(), 10.0, 0.001))

    let negative = Holder{angle: -12.0'deg}
    @assert(Math.isEqualEpsilon(negative.angle.rad, Math.toRadians(-12.0'f32), 0.001))
    @assert(Math.isEqualEpsilon(negative.angle.toDegrees(), -12.0, 0.001))
}
