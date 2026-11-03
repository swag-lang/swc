#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.clamp(5, 0, 10) == 5)
    Swag.require(Math.clamp(-1, 0, 10) == 0)
    Swag.require(Math.clamp(11, 0, 10) == 10)
    Swag.require(Math.clamp(2.5'f32, 3'f32, 4'f32) == 3'f32)

    Swag.require(Math.min(5, 2) == 2)
    Swag.require(Math.max(5, 2) == 5)
    Swag.require(Math.min(5, 2, -1) == -1)
    Swag.require(Math.max(5, 2, -1) == 5)
    Swag.require(Math.min(5, 2, -1, 9) == -1)
    Swag.require(Math.max(5, 2, -1, 9) == 9)
}

#test
{
    Swag.require(Math.bigEndianToNative(0x1234'u16) == 0x3412'u16)
    Swag.require(Math.nativeToBigEndian(0x12345678'u32) == 0x78563412'u32)
    Swag.require(Math.littleEndianToNative(0x12345678'u32) == 0x12345678'u32)
}

// Signed fields, and single bytes, travel through the same conversion family.
#test
{
    Swag.require(Math.nativeToBigEndian(800's16) == 0x2003's16)
    Swag.require(Math.bigEndianToNative(0x2003's16) == 800's16)
    Swag.require(Math.bigEndianToNative(Math.nativeToBigEndian(-800's16)) == -800's16)
    Swag.require(Math.bigEndianToNative(Math.nativeToBigEndian(-70000's32)) == -70000's32)
    Swag.require(Math.bigEndianToNative(Math.nativeToBigEndian(-5_000_000_000's64)) == -5_000_000_000's64)

    Swag.require(Math.littleEndianToNative(Math.nativeToLittleEndian(-800's16)) == -800's16)
    Swag.require(Math.littleEndianToNative(Math.nativeToLittleEndian(-70000's32)) == -70000's32)
    Swag.require(Math.littleEndianToNative(Math.nativeToLittleEndian(-5_000_000_000's64)) == -5_000_000_000's64)

    Swag.require(Math.nativeToBigEndian(200'u8) == 200'u8)
    Swag.require(Math.nativeToLittleEndian(-100's8) == -100's8)
    Swag.require(Math.bigEndianToNative(-100's8) == -100's8)
}
