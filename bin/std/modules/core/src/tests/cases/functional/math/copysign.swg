#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.copysign(3.5_f32, -1_f32) == -3.5_f32)
    Swag.require(Math.copysign(-3.5_f32, 1_f32) == 3.5_f32)
    Swag.require(cast #bit (u32, Math.copysign(0_f32, -1_f32)) == 0x80000000_u32)
    Swag.require(cast #bit (u32, Math.copysign(-0_f32, 1_f32)) == 0_u32)

    let payloadNaN = cast #bit (f32, 0x7FC12345_u32)
    let signedNaN  = Math.copysign(payloadNaN, -1_f32)
    Swag.require(cast #bit (u32, signedNaN) == 0xFFC12345_u32)
}

#test
{
    Swag.require(Math.copysign(3.5_f64, -1_f64) == -3.5_f64)
    Swag.require(Math.copysign(-3.5_f64, 1_f64) == 3.5_f64)
    Swag.require(cast #bit (u64, Math.copysign(0_f64, -1_f64)) == 0x8000000000000000_u64)
    Swag.require(cast #bit (u64, Math.copysign(-0_f64, 1_f64)) == 0_u64)

    let payloadNaN = cast #bit (f64, 0x7FF8123456789ABC_u64)
    let signedNaN  = Math.copysign(payloadNaN, -1_f64)
    Swag.require(cast #bit (u64, signedNaN) == 0xFFF8123456789ABC_u64)
}
