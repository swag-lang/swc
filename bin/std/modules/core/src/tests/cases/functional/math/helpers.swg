#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    Swag.require(Math.clamp(5, 0, 10) == 5)
    Swag.require(Math.clamp(-1, 0, 10) == 0)
    Swag.require(Math.clamp(11, 0, 10) == 10)
    Swag.require(Math.clamp(2.5_f32, 3_f32, 4_f32) == 3_f32)
    Swag.require(Math.clamp(5, 10, 0) == 10)

    Swag.require(Math.min(5, 2) == 2)
    Swag.require(Math.max(5, 2) == 5)
    Swag.require(Math.min(5, 2, -1) == -1)
    Swag.require(Math.max(5, 2, -1) == 5)
    Swag.require(Math.min(5, 2, -1, 9) == -1)
    Swag.require(Math.max(5, 2, -1, 9) == 9)
}

#test
{
    Swag.require(Math.bigEndianToNative(Math.nativeToBigEndian(0x12345678_u32)) == 0x12345678_u32)
    Swag.require(Math.littleEndianToNative(Math.nativeToLittleEndian(0x12345678_u32)) == 0x12345678_u32)

    #static if BIG_ENDIAN
    {
        Swag.require(Math.bigEndianToNative(0x1234_u16) == 0x1234_u16)
        Swag.require(Math.nativeToBigEndian(0x12345678_u32) == 0x12345678_u32)
        Swag.require(Math.littleEndianToNative(0x12345678_u32) == 0x78563412_u32)
    }
    else
    {
        Swag.require(Math.bigEndianToNative(0x1234_u16) == 0x3412_u16)
        Swag.require(Math.nativeToBigEndian(0x12345678_u32) == 0x78563412_u32)
        Swag.require(Math.littleEndianToNative(0x12345678_u32) == 0x12345678_u32)
    }
}

// Signed fields, and single bytes, travel through the same conversion family.
#test
{
    #static if BIG_ENDIAN
    {
        Swag.require(Math.nativeToBigEndian(800_s16) == 800_s16)
        Swag.require(Math.bigEndianToNative(800_s16) == 800_s16)
    }
    else
    {
        Swag.require(Math.nativeToBigEndian(800_s16) == 0x2003_s16)
        Swag.require(Math.bigEndianToNative(0x2003_s16) == 800_s16)
    }

    Swag.require(Math.bigEndianToNative(Math.nativeToBigEndian(-800_s16)) == -800_s16)
    Swag.require(Math.bigEndianToNative(Math.nativeToBigEndian(-70000_s32)) == -70000_s32)
    Swag.require(Math.bigEndianToNative(Math.nativeToBigEndian(-5_000_000_000_s64)) == -5_000_000_000_s64)

    Swag.require(Math.littleEndianToNative(Math.nativeToLittleEndian(-800_s16)) == -800_s16)
    Swag.require(Math.littleEndianToNative(Math.nativeToLittleEndian(-70000_s32)) == -70000_s32)
    Swag.require(Math.littleEndianToNative(Math.nativeToLittleEndian(-5_000_000_000_s64)) == -5_000_000_000_s64)

    Swag.require(Math.nativeToBigEndian(200_u8) == 200_u8)
    Swag.require(Math.nativeToLittleEndian(-100_s8) == -100_s8)
    Swag.require(Math.bigEndianToNative(-100_s8) == -100_s8)
}
