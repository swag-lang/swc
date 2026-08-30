#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let zero: Math.Angle = 0.0
    Swag.assert(zero.radians == 0.0)
    Swag.assert(zero.toDegrees() == 0.0)

    let zeroDeg: Math.Angle = 0.0'deg
    Swag.assert(zeroDeg.radians == 0.0)
    Swag.assert(zeroDeg.toDegrees() == 0.0)

    let zeroRad: Math.Angle = 0.0'rad
    Swag.assert(zeroRad.radians == 0.0)
    Swag.assert(zeroRad.toDegrees() == 0.0)

    let direct = Math.Angle.fromRadians(1.25)
    Swag.assert(direct.radians == 1.25)
    Swag.assert(Math.isEqualEpsilon(direct.toDegrees(), Math.toDegrees(1.25'f32), 0.001))

    let negativeDirect: Math.Angle = -Math.ConstF32.Pi
    Swag.assert(Math.isEqualEpsilon(negativeDirect.radians, -Math.ConstF32.Pi, 0.001))
    Swag.assert(Math.isEqualEpsilon(negativeDirect.toDegrees(), -180.0, 0.001))

    let quarterTurnDeg: Math.Angle = 90.0'deg
    Swag.assert(Math.isEqualEpsilon(quarterTurnDeg.radians, Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(quarterTurnDeg.toDegrees(), 90.0, 0.001))

    let halfTurn: Math.Angle = 180.0'deg
    Swag.assert(Math.isEqualEpsilon(halfTurn.radians, Math.ConstF32.Pi, 0.001))
    Swag.assert(Math.isEqualEpsilon(halfTurn.toDegrees(), 180.0, 0.001))

    let fullTurn: Math.Angle = 360.0'deg
    Swag.assert(Math.isEqualEpsilon(fullTurn.radians, Math.ConstF32.TwoPi, 0.001))
    Swag.assert(Math.isEqualEpsilon(fullTurn.toDegrees(), 360.0, 0.001))

    let negativeQuarterTurn: Math.Angle = -90.0'deg
    Swag.assert(Math.isEqualEpsilon(negativeQuarterTurn.radians, -Math.ConstF32.PiBy2, 0.001))
    Swag.assert(Math.isEqualEpsilon(negativeQuarterTurn.toDegrees(), -90.0, 0.001))

    let quarterTurn: Math.Angle = Math.ConstF32.PiBy2
    Swag.assert(Math.isEqualEpsilon(quarterTurn.toDegrees(), 90.0, 0.001))

    let directLiteral: Math.Angle = 1.25'rad
    Swag.assert(directLiteral.radians == 1.25)
    Swag.assert(Math.isEqualEpsilon(directLiteral.toDegrees(), Math.toDegrees(1.25'f32), 0.001))

    let negativeRadLiteral: Math.Angle = -1.25'rad
    Swag.assert(negativeRadLiteral.radians == -1.25)
    Swag.assert(Math.isEqualEpsilon(negativeRadLiteral.toDegrees(), Math.toDegrees(-1.25'f32), 0.001))
}

#test
{
    struct Holder
    {
        angle: Math.Angle
    }

    let positive = Holder{angle: 10.0'deg}
    Swag.assert(Math.isEqualEpsilon(positive.angle.radians, Math.toRadians(10.0'f32), 0.001))
    Swag.assert(Math.isEqualEpsilon(positive.angle.toDegrees(), 10.0, 0.001))

    let negative = Holder{angle: -12.0'deg}
    Swag.assert(Math.isEqualEpsilon(negative.angle.radians, Math.toRadians(-12.0'f32), 0.001))
    Swag.assert(Math.isEqualEpsilon(negative.angle.toDegrees(), -12.0, 0.001))
}
