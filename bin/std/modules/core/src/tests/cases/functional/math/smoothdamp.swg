#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var zeroVelocity:     f32 = 0
    var negativeVelocity: f32 = 0
    var minimumVelocity:  f32 = 0

    let zeroTime     = Math.smoothDamp(1_f32, 9_f32, &zeroVelocity, 0_f32, 0.1_f32)
    let negativeTime = Math.smoothDamp(1_f32, 9_f32, &negativeVelocity, -1_f32, 0.1_f32)
    let minimumTime  = Math.smoothDamp(1_f32, 9_f32, &minimumVelocity, 0.0001_f32, 0.1_f32)

    Swag.require(zeroTime == minimumTime and negativeTime == minimumTime)
    Swag.require(zeroVelocity == minimumVelocity and negativeVelocity == minimumVelocity)
}

#test
{
    var zeroVelocity:     f64 = 0
    var negativeVelocity: f64 = 0
    var minimumVelocity:  f64 = 0

    let zeroTime     = Math.smoothDamp(1_f64, 9_f64, &zeroVelocity, 0_f64, 0.1_f64)
    let negativeTime = Math.smoothDamp(1_f64, 9_f64, &negativeVelocity, -1_f64, 0.1_f64)
    let minimumTime  = Math.smoothDamp(1_f64, 9_f64, &minimumVelocity, 0.0001_f64, 0.1_f64)

    Swag.require(zeroTime == minimumTime and negativeTime == minimumTime)
    Swag.require(zeroVelocity == minimumVelocity and negativeVelocity == minimumVelocity)
}
