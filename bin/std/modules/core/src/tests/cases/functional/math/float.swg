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
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.OneByPi * Math.ConstF32.Pi, 1'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.TwoByPi * Math.ConstF32.Pi, 2'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Sqrt2 * Math.ConstF32.OneBySqrt2, 1'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Ln2, Math.log(2'f32), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Ln10, Math.log(10'f32), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Log2E, Math.log2(Math.ConstF32.E), 0.001))
    Swag.require(Math.isEqualEpsilon(Math.ConstF32.Log10E, Math.log10(Math.ConstF32.E), 0.001))
    Swag.require(Math.ConstF32.Epsilon > 0)
}

#test
{
    Swag.require(Math.sign(-2'f32) == -1'f32)
    Swag.require(Math.sign(0'f32) == 0'f32)
    Swag.require(Math.sign(2'f32) == 1'f32)
    Swag.require(Math.sign(-2'f64) == -1'f64)
    Swag.require(Math.sign(0'f64) == 0'f64)
    Swag.require(Math.sign(2'f64) == 1'f64)

    Swag.require(Math.saturate(-2'f32) == 0'f32)
    Swag.require(Math.saturate(0.25'f32) == 0.25'f32)
    Swag.require(Math.saturate(2'f32) == 1'f32)
    Swag.require(Math.saturate(-2'f64) == 0'f64)
    Swag.require(Math.saturate(0.25'f64) == 0.25'f64)
    Swag.require(Math.saturate(2'f64) == 1'f64)

    Swag.require(Math.lerp(2'f32, 10'f32, 0'f32) == 2'f32)
    Swag.require(Math.lerp(2'f32, 10'f32, 0.25'f32) == 4'f32)
    Swag.require(Math.lerp(2'f32, 10'f32, 1'f32) == 10'f32)
    Swag.require(Math.lerp(2'f64, 10'f64, 0'f64) == 2'f64)
    Swag.require(Math.lerp(2'f64, 10'f64, 0.25'f64) == 4'f64)
    Swag.require(Math.lerp(2'f64, 10'f64, 1'f64) == 10'f64)
    Swag.require(Math.lerp(-Swag.F32.Max, Swag.F32.Max, 0'f32) == -Swag.F32.Max)
    Swag.require(Math.lerp(-Swag.F32.Max, Swag.F32.Max, 0.5'f32) == 0'f32)
    Swag.require(Math.lerp(-Swag.F32.Max, Swag.F32.Max, 1'f32) == Swag.F32.Max)
    Swag.require(Math.lerp(-Swag.F64.Max, Swag.F64.Max, 0'f64) == -Swag.F64.Max)
    Swag.require(Math.lerp(-Swag.F64.Max, Swag.F64.Max, 0.5'f64) == 0'f64)
    Swag.require(Math.lerp(-Swag.F64.Max, Swag.F64.Max, 1'f64) == Swag.F64.Max)
    Swag.require(Math.lerp(2'f32, 10'f32, -0.5'f32) == -2'f32)
    Swag.require(Math.lerp(2'f32, 10'f32, 1.5'f32) == 14'f32)
    Swag.require(Math.lerp(2'f64, 10'f64, -0.5'f64) == -2'f64)
    Swag.require(Math.lerp(2'f64, 10'f64, 1.5'f64) == 14'f64)
    Swag.require(Math.isEqualEpsilon(Math.cubicLerp(0'f32, 10'f32, 20'f32, 30'f32, 0.5'f32), 15'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.cubicLerp(0'f64, 10'f64, 20'f64, 30'f64, 0.5'f64), 15'f64, 0.001))
    Swag.require(Math.interpHermite(0'f32) == 0'f32)
    Swag.require(Math.interpHermite(0.5'f32) == 0.5'f32)
    Swag.require(Math.interpHermite(1'f32) == 1'f32)
    Swag.require(Math.interpHermite(0'f64) == 0'f64)
    Swag.require(Math.interpHermite(0.5'f64) == 0.5'f64)
    Swag.require(Math.interpHermite(1'f64) == 1'f64)
    Swag.require(Math.interpQuintic(0'f32) == 0'f32)
    Swag.require(Math.interpQuintic(0.5'f32) == 0.5'f32)
    Swag.require(Math.interpQuintic(1'f32) == 1'f32)
    Swag.require(Math.interpQuintic(0'f64) == 0'f64)
    Swag.require(Math.interpQuintic(0.5'f64) == 0.5'f64)
    Swag.require(Math.interpQuintic(1'f64) == 1'f64)
    Swag.require(Math.fract(3.75'f32) == 0.75'f32)
    Swag.require(Math.fract(-1.75'f32) == 0.25'f32)
    Swag.require(Math.fract(3.75'f64) == 0.75'f64)
    Swag.require(Math.fract(-1.75'f64) == 0.25'f64)
}

#test
{
    Swag.require(Math.moveTowards(0'f32, 10'f32, 3'f32) == 3'f32)
    Swag.require(Math.moveTowards(8'f32, 10'f32, 3'f32) == 10'f32)
    Swag.require(Math.moveTowards(10'f32, 0'f32, 3'f32) == 7'f32)
    Swag.require(Math.moveTowards(10'f32, 10'f32, 3'f32) == 10'f32)
    Swag.require(Math.moveTowards(0'f64, 10'f64, 3'f64) == 3'f64)
    Swag.require(Math.moveTowards(8'f64, 10'f64, 3'f64) == 10'f64)
    Swag.require(Math.moveTowards(10'f64, 0'f64, 3'f64) == 7'f64)
    Swag.require(Math.moveTowards(10'f64, 10'f64, 3'f64) == 10'f64)

    var velocity = 0'f32
    let smoothed = Math.smoothDamp(0'f32, 10'f32, &velocity, 0.5'f32, 0.1'f32)
    Swag.require(smoothed > 0'f32 and smoothed < 10'f32)
    Swag.require(velocity > 0'f32)

    var velocity64 = 0'f64
    let smoothed64 = Math.smoothDamp(0'f64, 10'f64, &velocity64, 0.5'f64, 0.1'f64)
    Swag.require(smoothed64 > 0'f64 and smoothed64 < 10'f64)
    Swag.require(velocity64 > 0'f64)
}

#test
{
    var velocityUp32 = 1000'f32
    let valueUp32    = Math.smoothDamp(0'f32, 10'f32, &velocityUp32, 0.5'f32, 1'f32)
    Swag.require(valueUp32 == 10'f32 and velocityUp32 == 0'f32)

    var velocityDown32 = -1000'f32
    let valueDown32    = Math.smoothDamp(10'f32, 0'f32, &velocityDown32, 0.5'f32, 1'f32)
    Swag.require(valueDown32 == 0'f32 and velocityDown32 == 0'f32)

    var velocityUp64 = 1000'f64
    let valueUp64    = Math.smoothDamp(0'f64, 10'f64, &velocityUp64, 0.5'f64, 1'f64)
    Swag.require(valueUp64 == 10'f64 and velocityUp64 == 0'f64)

    var velocityDown64 = -1000'f64
    let valueDown64    = Math.smoothDamp(10'f64, 0'f64, &velocityDown64, 0.5'f64, 1'f64)
    Swag.require(valueDown64 == 0'f64 and velocityDown64 == 0'f64)
}

#test
{
    Swag.require(Math.toDegrees(0'f32) == 0'f32)
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF32.Pi), 180'f32, 0.001'f32))
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF32.TwoPi), 360'f32, 0.001'f32))
    Swag.require(Math.toRadians(0'f32) == 0'f32)
    Swag.require(Math.isEqualEpsilon(Math.toRadians(180'f32), Math.ConstF32.Pi, 0.001'f32))
    Swag.require(Math.toDegrees(0'f64) == 0'f64)
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF64.Pi), 180'f64, 0.001'f64))
    Swag.require(Math.isEqualEpsilon(Math.toDegrees(Math.ConstF64.TwoPi), 360'f64, 0.001'f64))
    Swag.require(Math.toRadians(0'f64) == 0'f64)
    Swag.require(Math.isEqualEpsilon(Math.toRadians(180'f64), Math.ConstF64.Pi, 0.001'f64))

    Swag.require(Math.isZeroEpsilon(0'f32, 0.001'f32))
    Swag.require(Math.isZeroEpsilon(0.00001'f32, 0.001'f32))
    Swag.require(not Math.isZeroEpsilon(0.01'f32, 0.001'f32))
    Swag.require(Math.isZeroEpsilon(0'f64, 0.001'f64))
    Swag.require(Math.isZeroEpsilon(0.00001'f64, 0.001'f64))
    Swag.require(not Math.isZeroEpsilon(0.01'f64, 0.001'f64))
    Swag.require(Math.isEqualEpsilon(1'f32, 1'f32, 0.001'f32))
    Swag.require(Math.isEqualEpsilon(1'f32, 1.00001'f32, 0.001'f32))
    Swag.require(not Math.isEqualEpsilon(1'f32, 1.01'f32, 0.001'f32))
    Swag.require(Math.isEqualEpsilon(1'f64, 1'f64, 0.001'f64))
    Swag.require(Math.isEqualEpsilon(1'f64, 1.00001'f64, 0.001'f64))
    Swag.require(not Math.isEqualEpsilon(1'f64, 1.01'f64, 0.001'f64))

    Swag.require(Math.isNaN(Swag.F32.NaN))
    Swag.require(Math.isNaN(Swag.F64.NaN))
    Swag.require(Math.isFinite(1'f32))
    Swag.require(Math.isFinite(1'f64))
    Swag.require(not Math.isFinite(Swag.F32.Inf))
    Swag.require(not Math.isFinite(Swag.F64.Inf))
    Swag.require(not Math.isFinite(Swag.F32.NaN))
    Swag.require(not Math.isFinite(Swag.F64.NaN))
    Swag.require(not Math.isFinite(-Swag.F32.Inf))
    Swag.require(not Math.isFinite(-Swag.F64.Inf))
}

#test
{
    Swag.require(Math.smoothstep(0'f32, 10'f32, -1'f32) == 0'f32)
    Swag.require(Math.smoothstep(0'f32, 10'f32, 5'f32) == 0.5'f32)
    Swag.require(Math.smoothstep(0'f32, 10'f32, 11'f32) == 1'f32)
    Swag.require(Math.smoothstep(0'f64, 10'f64, -1'f64) == 0'f64)
    Swag.require(Math.smoothstep(0'f64, 10'f64, 5'f64) == 0.5'f64)
    Swag.require(Math.smoothstep(0'f64, 10'f64, 11'f64) == 1'f64)

    Swag.require(Math.map(5'f32, 0'f32, 10'f32, 0'f32, 100'f32) == 50'f32)
    Swag.require(Math.map(0'f32, -1'f32, 1'f32, 10'f32, 20'f32) == 15'f32)
    Swag.require(Math.map(5'f64, 0'f64, 10'f64, 0'f64, 100'f64) == 50'f64)
    Swag.require(Math.map(0'f64, -1'f64, 1'f64, 10'f64, 20'f64) == 15'f64)

    Swag.require(Math.nextPowerOfTen(-1'f32) == 1)
    Swag.require(Math.nextPowerOfTen(0'f32) == 1)
    Swag.require(Math.nextPowerOfTen(1'f32) == 10)
    Swag.require(Math.nextPowerOfTen(99'f32) == 100)
    Swag.require(Math.nextPowerOfTen(100'f32) == 1000)
    Swag.require(Math.nextPowerOfTen(-1'f64) == 1)
    Swag.require(Math.nextPowerOfTen(0'f64) == 1)
    Swag.require(Math.nextPowerOfTen(1'f64) == 10)
    Swag.require(Math.nextPowerOfTen(99'f64) == 100)
    Swag.require(Math.nextPowerOfTen(100'f64) == 1000)
}

#test
{
    Swag.require(Math.isEqualEpsilon(Math.atan2(1'f32, 0'f32), Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.atan2(1'f64, 0'f64), Math.ConstF64.PiBy2, 0.001))
    Swag.require(Math.sqrt(9'f32) == 3'f32)
    Swag.require(Math.sqrt(9'f64) == 3'f64)
    Swag.require(Math.isEqualEpsilon(Math.sin(Math.ConstF32.PiBy2), 1'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.sin(Math.ConstF64.PiBy2), 1'f64, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.cos(0'f32), 1'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.cos(0'f64), 1'f64, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.tan(Math.ConstF32.PiBy4), 1'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.tan(Math.ConstF64.PiBy4), 1'f64, 0.001))
    Swag.require(Math.sinh(0'f32) == 0'f32)
    Swag.require(Math.sinh(0'f64) == 0'f64)
    Swag.require(Math.cosh(0'f32) == 1'f32)
    Swag.require(Math.cosh(0'f64) == 1'f64)
    Swag.require(Math.tanh(0'f32) == 0'f32)
    Swag.require(Math.tanh(0'f64) == 0'f64)
    Swag.require(Math.isEqualEpsilon(Math.asin(1'f32), Math.ConstF32.PiBy2, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.asin(1'f64), Math.ConstF64.PiBy2, 0.001))
    Swag.require(Math.acos(1'f32) == 0'f32)
    Swag.require(Math.acos(1'f64) == 0'f64)
    Swag.require(Math.isEqualEpsilon(Math.atan(1'f32), Math.ConstF32.PiBy4, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.atan(1'f64), Math.ConstF64.PiBy4, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.log(Math.ConstF32.E), 1'f32, 0.001))
    Swag.require(Math.isEqualEpsilon(Math.log(Math.ConstF64.E), 1'f64, 0.001))
    Swag.require(Math.log2(8'f32) == 3'f32)
    Swag.require(Math.log2(8'f64) == 3'f64)
    Swag.require(Math.log10(100'f32) == 2'f32)
    Swag.require(Math.log10(100'f64) == 2'f64)
}

#test
{
    Swag.require(Math.floor(1.75'f32) == 1'f32)
    Swag.require(Math.floor(-1.25'f32) == -2'f32)
    Swag.require(Math.floor(1.75'f64) == 1'f64)
    Swag.require(Math.floor(-1.25'f64) == -2'f64)
    Swag.require(Math.ceil(1.25'f32) == 2'f32)
    Swag.require(Math.ceil(-1.75'f32) == -1'f32)
    Swag.require(Math.ceil(1.25'f64) == 2'f64)
    Swag.require(Math.ceil(-1.75'f64) == -1'f64)
    Swag.require(Math.trunc(1.75'f32) == 1'f32)
    Swag.require(Math.trunc(-1.75'f32) == -1'f32)
    Swag.require(Math.trunc(1.75'f64) == 1'f64)
    Swag.require(Math.trunc(-1.75'f64) == -1'f64)
    Swag.require(Math.round(1.5'f32) == 2'f32)
    Swag.require(Math.round(-1.5'f32) == -2'f32)
    Swag.require(Math.round(1.5'f64) == 2'f64)
    Swag.require(Math.round(-1.5'f64) == -2'f64)
    Swag.require(Math.floorS32(1.75'f32) == 1)
    Swag.require(Math.floorS32(-1.25'f32) == -2)
    Swag.require(Math.ceilS32(1.25'f32) == 2)
    Swag.require(Math.ceilS32(-1.75'f32) == -1)
    Swag.require(Math.truncS32(1.75'f32) == 1)
    Swag.require(Math.truncS32(-1.75'f32) == -1)
    Swag.require(Math.roundS32(1.5'f32) == 2)
    Swag.require(Math.roundS32(-1.5'f32) == -2)
    Swag.require(Math.floorS64(1.75'f64) == 1)
    Swag.require(Math.floorS64(-1.25'f64) == -2)
    Swag.require(Math.ceilS64(1.25'f64) == 2)
    Swag.require(Math.ceilS64(-1.75'f64) == -1)
    Swag.require(Math.truncS64(1.75'f64) == 1)
    Swag.require(Math.truncS64(-1.75'f64) == -1)
    Swag.require(Math.roundS64(1.5'f64) == 2)
    Swag.require(Math.roundS64(-1.5'f64) == -2)

    Swag.require(Math.abs(-2'f32) == 2'f32)
    Swag.require(Math.abs(0'f32) == 0'f32)
    Swag.require(Math.abs(-2'f64) == 2'f64)
    Swag.require(Math.abs(0'f64) == 0'f64)
    Swag.require(Math.min(2'f32, -1'f32) == -1'f32)
    Swag.require(Math.min(-1'f32, -1'f32) == -1'f32)
    Swag.require(Math.max(2'f32, -1'f32) == 2'f32)
    Swag.require(Math.max(-1'f32, -1'f32) == -1'f32)
    Swag.require(Math.min(2'f64, -1'f64) == -1'f64)
    Swag.require(Math.min(-1'f64, -1'f64) == -1'f64)
    Swag.require(Math.max(2'f64, -1'f64) == 2'f64)
    Swag.require(Math.max(-1'f64, -1'f64) == -1'f64)
}

#test
{
    Swag.require(Math.exp(0'f32) == 1'f32)
    Swag.require(Math.exp(0'f64) == 1'f64)
    Swag.require(Math.exp2(3'f32) == 8'f32)
    Swag.require(Math.exp2(3'f64) == 8'f64)
    Swag.require(Math.pow(2'f32, 3'f32) == 8'f32)
    Swag.require(Math.pow(2'f64, 3'f64) == 8'f64)
    Swag.require(Math.mulAdd(2'f32, 3'f32, 4'f32) == 10'f32)
    Swag.require(Math.mulAdd(2'f64, 3'f64, 4'f64) == 10'f64)
}
