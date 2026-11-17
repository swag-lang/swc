#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var zeroVelocity:    f32 = 0
    var negativeVelocity: f32 = 0
    var minimumVelocity:  f32 = 0

    let zeroTime = Math.smoothDamp(1'f32, 9'f32, &zeroVelocity, 0'f32, 0.1'f32)
    let negativeTime = Math.smoothDamp(1'f32, 9'f32, &negativeVelocity, -1'f32, 0.1'f32)
    let minimumTime = Math.smoothDamp(1'f32, 9'f32, &minimumVelocity, 0.0001'f32, 0.1'f32)

    Swag.require(zeroTime == minimumTime and negativeTime == minimumTime)
    Swag.require(zeroVelocity == minimumVelocity and negativeVelocity == minimumVelocity)
}

#test
{
    var zeroVelocity:    f64 = 0
    var negativeVelocity: f64 = 0
    var minimumVelocity:  f64 = 0

    let zeroTime = Math.smoothDamp(1'f64, 9'f64, &zeroVelocity, 0'f64, 0.1'f64)
    let negativeTime = Math.smoothDamp(1'f64, 9'f64, &negativeVelocity, -1'f64, 0.1'f64)
    let minimumTime = Math.smoothDamp(1'f64, 9'f64, &minimumVelocity, 0.0001'f64, 0.1'f64)

    Swag.require(zeroTime == minimumTime and negativeTime == minimumTime)
    Swag.require(zeroVelocity == minimumVelocity and negativeVelocity == minimumVelocity)
}
