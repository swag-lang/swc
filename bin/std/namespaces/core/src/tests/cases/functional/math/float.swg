#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.TwoPi, Math.ConstF32.Pi * 2, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.PiBy2, Math.ConstF32.Pi / 2, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.PiBy3, Math.ConstF32.Pi / 3, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.PiBy4, Math.ConstF32.Pi / 4, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.PiBy6, Math.ConstF32.Pi / 6, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.PiBy8, Math.ConstF32.Pi / 8, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.ThreePiBy4, Math.ConstF32.Pi * 0.75, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.OneByPi * Math.ConstF32.Pi, 1_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.TwoByPi * Math.ConstF32.Pi, 2_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Sqrt2 * Math.ConstF32.OneBySqrt2, 1_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Ln2, Math.log(2_f32), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Ln10, Math.log(10_f32), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Log2E, Math.log2(Math.ConstF32.E), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Log10E, Math.log10(Math.ConstF32.E), 0.001))
    Swag.require(Math.ConstF32.Epsilon > 0)
}

#test
{
    Swag.require(Math.sign(-2_f32) == -1_f32)
    Swag.require(Math.sign(0_f32) == 0_f32)
    Swag.require(Math.sign(2_f32) == 1_f32)
    Swag.require(Math.sign(-2_f64) == -1_f64)
    Swag.require(Math.sign(0_f64) == 0_f64)
    Swag.require(Math.sign(2_f64) == 1_f64)

    Swag.require(Math.saturate(-2_f32) == 0_f32)
    Swag.require(Math.saturate(0.25_f32) == 0.25_f32)
    Swag.require(Math.saturate(2_f32) == 1_f32)
    Swag.require(Math.saturate(-2_f64) == 0_f64)
    Swag.require(Math.saturate(0.25_f64) == 0.25_f64)
    Swag.require(Math.saturate(2_f64) == 1_f64)

    Swag.require(Math.lerp(2_f32, 10_f32, 0_f32) == 2_f32)
    Swag.require(Math.lerp(2_f32, 10_f32, 0.25_f32) == 4_f32)
    Swag.require(Math.lerp(2_f32, 10_f32, 1_f32) == 10_f32)
    Swag.require(Math.lerp(2_f64, 10_f64, 0_f64) == 2_f64)
    Swag.require(Math.lerp(2_f64, 10_f64, 0.25_f64) == 4_f64)
    Swag.require(Math.lerp(2_f64, 10_f64, 1_f64) == 10_f64)
    Swag.require(Math.lerp(-Swag.F32.Max, Swag.F32.Max, 0_f32) == -Swag.F32.Max)
    Swag.require(Math.lerp(-Swag.F32.Max, Swag.F32.Max, 0.5_f32) == 0_f32)
    Swag.require(Math.lerp(-Swag.F32.Max, Swag.F32.Max, 1_f32) == Swag.F32.Max)
    Swag.require(Math.lerp(-Swag.F64.Max, Swag.F64.Max, 0_f64) == -Swag.F64.Max)
    Swag.require(Math.lerp(-Swag.F64.Max, Swag.F64.Max, 0.5_f64) == 0_f64)
    Swag.require(Math.lerp(-Swag.F64.Max, Swag.F64.Max, 1_f64) == Swag.F64.Max)
    Swag.require(Math.lerp(2_f32, 10_f32, -0.5_f32) == -2_f32)
    Swag.require(Math.lerp(2_f32, 10_f32, 1.5_f32) == 14_f32)
    Swag.require(Math.lerp(2_f64, 10_f64, -0.5_f64) == -2_f64)
    Swag.require(Math.lerp(2_f64, 10_f64, 1.5_f64) == 14_f64)
    Swag.require(Math.isEqualEpsilon(Math.cubicLerp(0_f32, 10_f32, 20_f32, 30_f32, 0.5_f32), 15_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.cubicLerp(0_f64, 10_f64, 20_f64, 30_f64, 0.5_f64), 15_f64, 0.001))
    Swag.require(Math.interpHermite(0_f32) == 0_f32)
    Swag.require(Math.interpHermite(0.5_f32) == 0.5_f32)
    Swag.require(Math.interpHermite(1_f32) == 1_f32)
    Swag.require(Math.interpHermite(0_f64) == 0_f64)
    Swag.require(Math.interpHermite(0.5_f64) == 0.5_f64)
    Swag.require(Math.interpHermite(1_f64) == 1_f64)
    Swag.require(Math.interpQuintic(0_f32) == 0_f32)
    Swag.require(Math.interpQuintic(0.5_f32) == 0.5_f32)
    Swag.require(Math.interpQuintic(1_f32) == 1_f32)
    Swag.require(Math.interpQuintic(0_f64) == 0_f64)
    Swag.require(Math.interpQuintic(0.5_f64) == 0.5_f64)
    Swag.require(Math.interpQuintic(1_f64) == 1_f64)
    Swag.require(Math.fract(3.75_f32) == 0.75_f32)
    Swag.require(Math.fract(-1.75_f32) == 0.25_f32)
    Swag.require(Math.fract(3.75_f64) == 0.75_f64)
    Swag.require(Math.fract(-1.75_f64) == 0.25_f64)
}

#test
{
    Swag.require(Math.moveTowards(0_f32, 10_f32, 3_f32) == 3_f32)
    Swag.require(Math.moveTowards(8_f32, 10_f32, 3_f32) == 10_f32)
    Swag.require(Math.moveTowards(10_f32, 0_f32, 3_f32) == 7_f32)
    Swag.require(Math.moveTowards(10_f32, 10_f32, 3_f32) == 10_f32)
    Swag.require(Math.moveTowards(0_f32, 10_f32, -3_f32) == -3_f32)
    Swag.require(Math.moveTowards(10_f32, 10_f32, -3_f32) == 10_f32)
    Swag.require(Math.moveTowards(0_f64, 10_f64, 3_f64) == 3_f64)
    Swag.require(Math.moveTowards(8_f64, 10_f64, 3_f64) == 10_f64)
    Swag.require(Math.moveTowards(10_f64, 0_f64, 3_f64) == 7_f64)
    Swag.require(Math.moveTowards(10_f64, 10_f64, 3_f64) == 10_f64)
    Swag.require(Math.moveTowards(0_f64, 10_f64, -3_f64) == -3_f64)
    Swag.require(Math.moveTowards(10_f64, 10_f64, -3_f64) == 10_f64)

    var velocity = 0_f32
    let smoothed = Math.smoothDamp(0_f32, 10_f32, &velocity, 0.5_f32, 0.1_f32)
    Swag.require(smoothed > 0_f32 and smoothed < 10_f32)
    Swag.require(velocity > 0_f32)

    var velocity64 = 0_f64
    let smoothed64 = Math.smoothDamp(0_f64, 10_f64, &velocity64, 0.5_f64, 0.1_f64)
    Swag.require(smoothed64 > 0_f64 and smoothed64 < 10_f64)
    Swag.require(velocity64 > 0_f64)
}

#test
{
    var velocityUp32 = 1000_f32
    let valueUp32    = Math.smoothDamp(0_f32, 10_f32, &velocityUp32, 0.5_f32, 1_f32)
    Swag.require(valueUp32 == 10_f32 and velocityUp32 == 0_f32)

    var velocityDown32 = -1000_f32
    let valueDown32    = Math.smoothDamp(10_f32, 0_f32, &velocityDown32, 0.5_f32, 1_f32)
    Swag.require(valueDown32 == 0_f32 and velocityDown32 == 0_f32)

    var velocityUp64 = 1000_f64
    let valueUp64    = Math.smoothDamp(0_f64, 10_f64, &velocityUp64, 0.5_f64, 1_f64)
    Swag.require(valueUp64 == 10_f64 and velocityUp64 == 0_f64)

    var velocityDown64 = -1000_f64
    let valueDown64    = Math.smoothDamp(10_f64, 0_f64, &velocityDown64, 0.5_f64, 1_f64)
    Swag.require(valueDown64 == 0_f64 and velocityDown64 == 0_f64)
}

#test
{
    Swag.require(Math.toDegrees(0_f32) == 0_f32)
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF32.Pi), 180_f32, 0.001_f32))
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF32.TwoPi), 360_f32, 0.001_f32))
    Swag.require(Math.toRadians(0_f32) == 0_f32)
    Swag.require(Math.isEqualEpsilon(Math.toRadians(180_f32), Math.ConstF32.Pi, 0.001_f32))
    Swag.require(Math.toDegrees(0_f64) == 0_f64)
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF64.Pi), 180_f64, 0.001_f64))
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF64.TwoPi), 360_f64, 0.001_f64))
    Swag.require(Math.toRadians(0_f64) == 0_f64)
    Swag.require(Math.isEqualEpsilon(Math.toRadians(180_f64), Math.ConstF64.Pi, 0.001_f64))

    Swag.require(Math.isZeroEpsilon(0_f32, 0.001_f32))
    Swag.require(Math.isZeroEpsilon(0.00001_f32, 0.001_f32))
    Swag.require(not Math.isZeroEpsilon(0.01_f32, 0.001_f32))
    Swag.require(Math.isZeroEpsilon(0_f64, 0.001_f64))
    Swag.require(Math.isZeroEpsilon(0.00001_f64, 0.001_f64))
    Swag.require(not Math.isZeroEpsilon(0.01_f64, 0.001_f64))
    Swag.require(Math.isEqualEpsilon(1_f32, 1_f32, 0.001_f32))
    Swag.require(Math.isEqualEpsilon(1_f32, 1.00001_f32, 0.001_f32))
    Swag.require(not Math.isEqualEpsilon(1_f32, 1.01_f32, 0.001_f32))
    Swag.require(Math.isEqualEpsilon(1_f64, 1_f64, 0.001_f64))
    Swag.require(Math.isEqualEpsilon(1_f64, 1.00001_f64, 0.001_f64))
    Swag.require(not Math.isEqualEpsilon(1_f64, 1.01_f64, 0.001_f64))

    Swag.require(Math.isNaN(Swag.F32.NaN))
    Swag.require(Math.isNaN(Swag.F64.NaN))
    Swag.require(Math.isFinite(1_f32))
    Swag.require(Math.isFinite(1_f64))
    Swag.require(not Math.isFinite(Swag.F32.Inf))
    Swag.require(not Math.isFinite(Swag.F64.Inf))
    Swag.require(not Math.isFinite(Swag.F32.NaN))
    Swag.require(not Math.isFinite(Swag.F64.NaN))
    Swag.require(not Math.isFinite(-Swag.F32.Inf))
    Swag.require(not Math.isFinite(-Swag.F64.Inf))
}

#test
{
    Swag.require(Math.smoothstep(0_f32, 10_f32, -1_f32) == 0_f32)
    Swag.require(Math.smoothstep(0_f32, 10_f32, 5_f32) == 0.5_f32)
    Swag.require(Math.smoothstep(0_f32, 10_f32, 11_f32) == 1_f32)
    Swag.require(Math.smoothstep(0_f64, 10_f64, -1_f64) == 0_f64)
    Swag.require(Math.smoothstep(0_f64, 10_f64, 5_f64) == 0.5_f64)
    Swag.require(Math.smoothstep(0_f64, 10_f64, 11_f64) == 1_f64)

    Swag.require(Math.map(5_f32, 0_f32, 10_f32, 0_f32, 100_f32) == 50_f32)
    Swag.require(Math.map(0_f32, -1_f32, 1_f32, 10_f32, 20_f32) == 15_f32)
    Swag.require(Math.map(5_f64, 0_f64, 10_f64, 0_f64, 100_f64) == 50_f64)
    Swag.require(Math.map(0_f64, -1_f64, 1_f64, 10_f64, 20_f64) == 15_f64)

    Swag.require(Math.nextPowerOfTen(-1_f32) == 1)
    Swag.require(Math.nextPowerOfTen(0_f32) == 1)
    Swag.require(Math.nextPowerOfTen(1_f32) == 10)
    Swag.require(Math.nextPowerOfTen(99_f32) == 100)
    Swag.require(Math.nextPowerOfTen(100_f32) == 1000)
    Swag.require(Math.nextPowerOfTen(-1_f64) == 1)
    Swag.require(Math.nextPowerOfTen(0_f64) == 1)
    Swag.require(Math.nextPowerOfTen(1_f64) == 10)
    Swag.require(Math.nextPowerOfTen(99_f64) == 100)
    Swag.require(Math.nextPowerOfTen(100_f64) == 1000)
}

#test
{
    Swag.require(Math.inverseLerp(0_f32, 10_f32, 2_f32) == 0.2_f32)
    Swag.require(Math.inverseLerp(10_f32, 0_f32, 2_f32) == 0.8_f32)
    Swag.require(Math.inverseLerp(0_f64, 10_f64, 2_f64) == 0.2_f64)
    Swag.require(Math.inverseLerp(10_f64, 0_f64, 2_f64) == 0.8_f64)

    Swag.require(Math.wrap(2.25_f32, 0_f32, 1_f32) == 0.25_f32)
    Swag.require(Math.wrap(-0.25_f32, 0_f32, 1_f32) == 0.75_f32)
    Swag.require(Math.wrap(3_f32, -1_f32, 2_f32) == 0_f32)
    Swag.require(Math.wrap(2.25_f64, 0_f64, 1_f64) == 0.25_f64)
    Swag.require(Math.wrap(-0.25_f64, 0_f64, 1_f64) == 0.75_f64)

    Swag.require(Math.pingPong(0_f32, 3_f32) == 0_f32)
    Swag.require(Math.pingPong(2_f32, 3_f32) == 2_f32)
    Swag.require(Math.pingPong(4_f32, 3_f32) == 2_f32)
    Swag.require(Math.pingPong(-2_f32, 3_f32) == 2_f32)
    Swag.require(Math.pingPong(4_f64, 3_f64) == 2_f64)

    Swag.require(Math.isEqualEpsilon(Math.deltaAngle(0_f32, Math.ConstF32.PiBy2), Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.deltaAngle(Math.toRadians(170_f32), Math.toRadians(-170_f32)), Math.toRadians(20_f32), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.deltaAngle(Math.toRadians(-170_f64), Math.toRadians(170_f64)), Math.toRadians(-20_f64), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.lerpAngle(Math.toRadians(170_f32), Math.toRadians(-170_f32), 0.5_f32), Math.ConstF32.Pi, 0.001))
}

#test
{
    Swag.require(Math.isEqualEpsilon(Math.atan2(1_f32, 0_f32), Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.atan2(1_f64, 0_f64), Math.ConstF64.PiBy2, 0.001))
    Swag.require(Math.sqrt(9_f32) == 3_f32)
    Swag.require(Math.sqrt(9_f64) == 3_f64)
    Swag.require(Math.isEqualEpsilon(Math.sin(Math.ConstF32.PiBy2), 1_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.sin(Math.ConstF64.PiBy2), 1_f64, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.cos(0_f32), 1_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.cos(0_f64), 1_f64, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.tan(Math.ConstF32.PiBy4), 1_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.tan(Math.ConstF64.PiBy4), 1_f64, 0.001))
    Swag.require(Math.sinh(0_f32) == 0_f32)
    Swag.require(Math.sinh(0_f64) == 0_f64)
    Swag.require(Math.cosh(0_f32) == 1_f32)
    Swag.require(Math.cosh(0_f64) == 1_f64)
    Swag.require(Math.tanh(0_f32) == 0_f32)
    Swag.require(Math.tanh(0_f64) == 0_f64)
    Swag.require(Math.isEqualEpsilon(Math.asin(1_f32), Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.asin(1_f64), Math.ConstF64.PiBy2, 0.001))
    Swag.require(Math.acos(1_f32) == 0_f32)
    Swag.require(Math.acos(1_f64) == 0_f64)
    Swag.require(Math.isEqualEpsilon(Math.atan(1_f32), Math.ConstF32.PiBy4, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.atan(1_f64), Math.ConstF64.PiBy4, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.log(Math.ConstF32.E), 1_f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.log(Math.ConstF64.E), 1_f64, 0.001))
    Swag.require(Math.log2(8_f32) == 3_f32)
    Swag.require(Math.log2(8_f64) == 3_f64)
    Swag.require(Math.log10(100_f32) == 2_f32)
    Swag.require(Math.log10(100_f64) == 2_f64)
}

#test
{
    Swag.require(Math.floor(1.75_f32) == 1_f32)
    Swag.require(Math.floor(-1.25_f32) == -2_f32)
    Swag.require(Math.floor(1.75_f64) == 1_f64)
    Swag.require(Math.floor(-1.25_f64) == -2_f64)
    Swag.require(Math.ceil(1.25_f32) == 2_f32)
    Swag.require(Math.ceil(-1.75_f32) == -1_f32)
    Swag.require(Math.ceil(1.25_f64) == 2_f64)
    Swag.require(Math.ceil(-1.75_f64) == -1_f64)
    Swag.require(Math.trunc(1.75_f32) == 1_f32)
    Swag.require(Math.trunc(-1.75_f32) == -1_f32)
    Swag.require(Math.trunc(1.75_f64) == 1_f64)
    Swag.require(Math.trunc(-1.75_f64) == -1_f64)
    Swag.require(Math.round(1.5_f32) == 2_f32)
    Swag.require(Math.round(-1.5_f32) == -2_f32)
    Swag.require(Math.round(1.5_f64) == 2_f64)
    Swag.require(Math.round(-1.5_f64) == -2_f64)
    Swag.require(Math.floorS32(1.75_f32) == 1)
    Swag.require(Math.floorS32(-1.25_f32) == -2)
    Swag.require(Math.ceilS32(1.25_f32) == 2)
    Swag.require(Math.ceilS32(-1.75_f32) == -1)
    Swag.require(Math.truncS32(1.75_f32) == 1)
    Swag.require(Math.truncS32(-1.75_f32) == -1)
    Swag.require(Math.roundS32(1.5_f32) == 2)
    Swag.require(Math.roundS32(-1.5_f32) == -2)
    Swag.require(Math.floorS64(1.75_f64) == 1)
    Swag.require(Math.floorS64(-1.25_f64) == -2)
    Swag.require(Math.ceilS64(1.25_f64) == 2)
    Swag.require(Math.ceilS64(-1.75_f64) == -1)
    Swag.require(Math.truncS64(1.75_f64) == 1)
    Swag.require(Math.truncS64(-1.75_f64) == -1)
    Swag.require(Math.roundS64(1.5_f64) == 2)
    Swag.require(Math.roundS64(-1.5_f64) == -2)

    Swag.require(Math.abs(-2_f32) == 2_f32)
    Swag.require(Math.abs(0_f32) == 0_f32)
    Swag.require(Math.abs(-2_f64) == 2_f64)
    Swag.require(Math.abs(0_f64) == 0_f64)
    Swag.require(Math.min(2_f32, -1_f32) == -1_f32)
    Swag.require(Math.min(-1_f32, -1_f32) == -1_f32)
    Swag.require(Math.max(2_f32, -1_f32) == 2_f32)
    Swag.require(Math.max(-1_f32, -1_f32) == -1_f32)
    Swag.require(Math.min(2_f64, -1_f64) == -1_f64)
    Swag.require(Math.min(-1_f64, -1_f64) == -1_f64)
    Swag.require(Math.max(2_f64, -1_f64) == 2_f64)
    Swag.require(Math.max(-1_f64, -1_f64) == -1_f64)
}

#test
{
    Swag.require(Math.exp(0_f32) == 1_f32)
    Swag.require(Math.exp(0_f64) == 1_f64)
    Swag.require(Math.exp2(3_f32) == 8_f32)
    Swag.require(Math.exp2(3_f64) == 8_f64)
    Swag.require(Math.pow(2_f32, 3_f32) == 8_f32)
    Swag.require(Math.pow(2_f64, 3_f64) == 8_f64)
    Swag.require(Math.mulAdd(2_f32, 3_f32, 4_f32) == 10_f32)
    Swag.require(Math.mulAdd(2_f64, 3_f64, 4_f64) == 10_f64)
}
