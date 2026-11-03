#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let zero: Math.Angle = 0.0
    Swag.require(zero.radians == 0.0)
    Swag.require(zero.toDegrees() == 0.0)

    let zeroDeg: Math.Angle = 0.0'deg
    Swag.require(zeroDeg.radians == 0.0)
    Swag.require(zeroDeg.toDegrees() == 0.0)

    let zeroRad: Math.Angle = 0.0'rad
    Swag.require(zeroRad.radians == 0.0)
    Swag.require(zeroRad.toDegrees() == 0.0)

    let direct = Math.Angle.fromRadians(1.25)
    Swag.require(direct.radians == 1.25)
    Swag.require(Math.isEqualEpsilon(direct.toDegrees(), Math.toDegrees(1.25'f32), 0.001))

    let negativeDirect: Math.Angle = -Math.ConstF32.Pi
    Swag.require(Math.isEqualEpsilon(negativeDirect.radians, -Math.ConstF32.Pi, 0.001))
    Swag.require(Math.isEqualEpsilon(negativeDirect.toDegrees(), -180.0, 0.001))

    let quarterTurnDeg: Math.Angle = 90.0'deg
    Swag.require(Math.isEqualEpsilon(quarterTurnDeg.radians, Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(quarterTurnDeg.toDegrees(), 90.0, 0.001))

    let halfTurn: Math.Angle = 180.0'deg
    Swag.require(Math.isEqualEpsilon(halfTurn.radians, Math.ConstF32.Pi, 0.001))
    Swag.require(Math.isEqualEpsilon(halfTurn.toDegrees(), 180.0, 0.001))

    let fullTurn: Math.Angle = 360.0'deg
    Swag.require(Math.isEqualEpsilon(fullTurn.radians, Math.ConstF32.TwoPi, 0.001))
    Swag.require(Math.isEqualEpsilon(fullTurn.toDegrees(), 360.0, 0.001))

    let negativeQuarterTurn: Math.Angle = -90.0'deg
    Swag.require(Math.isEqualEpsilon(negativeQuarterTurn.radians, -Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(negativeQuarterTurn.toDegrees(), -90.0, 0.001))

    let quarterTurn: Math.Angle = Math.ConstF32.PiBy2
    Swag.require(Math.isEqualEpsilon(quarterTurn.toDegrees(), 90.0, 0.001))

    let directLiteral: Math.Angle = 1.25'rad
    Swag.require(directLiteral.radians == 1.25)
    Swag.require(Math.isEqualEpsilon(directLiteral.toDegrees(), Math.toDegrees(1.25'f32), 0.001))

    let negativeRadLiteral: Math.Angle = -1.25'rad
    Swag.require(negativeRadLiteral.radians == -1.25)
    Swag.require(Math.isEqualEpsilon(negativeRadLiteral.toDegrees(), Math.toDegrees(-1.25'f32), 0.001))
}

#test
{
    struct Holder
    {
        angle: Math.Angle
    }

    let positive = Holder{angle: 10.0'deg}
    Swag.require(Math.isEqualEpsilon(positive.angle.radians, Math.toRadians(10.0'f32), 0.001))
    Swag.require(Math.isEqualEpsilon(positive.angle.toDegrees(), 10.0, 0.001))

    let negative = Holder{angle: -12.0'deg}
    Swag.require(Math.isEqualEpsilon(negative.angle.radians, Math.toRadians(-12.0'f32), 0.001))
    Swag.require(Math.isEqualEpsilon(negative.angle.toDegrees(), -12.0, 0.001))
}
