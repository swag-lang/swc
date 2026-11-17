#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    let quarterTurn = Math.Angle.fromDegrees(90'f32)
    let negativeTurn = Math.Angle.fromDegrees(-45'f32)

    Swag.require(Math.isEqualEpsilon(quarterTurn.radians, Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(quarterTurn.toDegrees(), 90'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(negativeTurn.radians, -Math.ConstF32.PiBy4, 0.001))
    Swag.require(Math.isEqualEpsilon(negativeTurn.toDegrees(), -45'f32, 0.001))
}
