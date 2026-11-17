#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.copysign(3.5'f32, -1'f32) == -3.5'f32)
    Swag.require(Math.copysign(-3.5'f32, 1'f32) == 3.5'f32)
    Swag.require(cast #bit (u32, Math.copysign(0'f32, -1'f32)) == 0x80000000'u32)
    Swag.require(cast #bit (u32, Math.copysign(-0'f32, 1'f32)) == 0'u32)

    let payloadNaN = cast #bit (f32, 0x7FC12345'u32)
    let signedNaN  = Math.copysign(payloadNaN, -1'f32)
    Swag.require(cast #bit (u32, signedNaN) == 0xFFC12345'u32)
}

#test
{
    Swag.require(Math.copysign(3.5'f64, -1'f64) == -3.5'f64)
    Swag.require(Math.copysign(-3.5'f64, 1'f64) == 3.5'f64)
    Swag.require(cast #bit (u64, Math.copysign(0'f64, -1'f64)) == 0x8000000000000000'u64)
    Swag.require(cast #bit (u64, Math.copysign(-0'f64, 1'f64)) == 0'u64)

    let payloadNaN = cast #bit (f64, 0x7FF8123456789ABC'u64)
    let signedNaN  = Math.copysign(payloadNaN, -1'f64)
    Swag.require(cast #bit (u64, signedNaN) == 0xFFF8123456789ABC'u64)
}
