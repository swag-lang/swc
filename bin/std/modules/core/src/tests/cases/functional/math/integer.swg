#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func expectedHasZeroByte16(value: u16)->bool => (value & 0x00FF) == 0 or (value & 0xFF00) == 0

func expectedHasByte16(value: u16, byte: u8)->bool
{
    let expected = cast(u16, byte)
    return (value & 0x00FF) == expected or ((value >> 8) & 0x00FF) == expected
}

func expectedSign8(value: s8)->s8
{
    if value < 0
    {
        return -1
    }

    if value > 0
    {
        return 1
    }

    return 0
}

func expectedAbs8(value: s8)->s8
{
    if value < 0
    {
        return -value
    }

    return value
}

#test
{
    Swag.require(Math.byteAt(0xA5_u8, 0) == 0xA5_u8)

    Swag.require(Math.byteAt(0x1234_u16, 0) == 0x34_u8)
    Swag.require(Math.byteAt(0x1234_u16, 1) == 0x12_u8)

    Swag.require(Math.byteAt(0x12345678_u32, 0) == 0x78_u8)
    Swag.require(Math.byteAt(0x12345678_u32, 1) == 0x56_u8)
    Swag.require(Math.byteAt(0x12345678_u32, 2) == 0x34_u8)
    Swag.require(Math.byteAt(0x12345678_u32, 3) == 0x12_u8)

    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 0) == 0xEF_u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 1) == 0xCD_u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 2) == 0xAB_u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 3) == 0x89_u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 4) == 0x67_u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 5) == 0x45_u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 6) == 0x23_u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF_u64, 7) == 0x01_u8)
}

#test
{
    Swag.require(Math.sign(Swag.S8.Min) == -1_s8)
    Swag.require(Math.sign(Swag.S8.Max) == 1_s8)
    Swag.require(Math.min(Swag.S8.Min, Swag.S8.Max) == Swag.S8.Min)
    Swag.require(Math.max(Swag.S8.Min, Swag.S8.Max) == Swag.S8.Max)

    Swag.require(Math.sign(Swag.S16.Min) == -1_s16)
    Swag.require(Math.sign(Swag.S16.Max) == 1_s16)
    Swag.require(Math.min(Swag.S16.Min, Swag.S16.Max) == Swag.S16.Min)
    Swag.require(Math.max(Swag.S16.Min, Swag.S16.Max) == Swag.S16.Max)

    Swag.require(Math.sign(Swag.S32.Min) == -1_s32)
    Swag.require(Math.sign(Swag.S32.Max) == 1_s32)
    Swag.require(Math.min(Swag.S32.Min, Swag.S32.Max) == Swag.S32.Min)
    Swag.require(Math.max(Swag.S32.Min, Swag.S32.Max) == Swag.S32.Max)

    Swag.require(Math.sign(Swag.S64.Min) == -1_s64)
    Swag.require(Math.sign(Swag.S64.Max) == 1_s64)
    Swag.require(Math.min(Swag.S64.Min, Swag.S64.Max) == Swag.S64.Min)
    Swag.require(Math.max(Swag.S64.Min, Swag.S64.Max) == Swag.S64.Max)

    Swag.require(Math.min(0_u8, Swag.U8.Max) == 0_u8)
    Swag.require(Math.max(0_u8, Swag.U8.Max) == Swag.U8.Max)
    Swag.require(Math.min(0_u16, Swag.U16.Max) == 0_u16)
    Swag.require(Math.max(0_u16, Swag.U16.Max) == Swag.U16.Max)
    Swag.require(Math.min(0_u32, Swag.U32.Max) == 0_u32)
    Swag.require(Math.max(0_u32, Swag.U32.Max) == Swag.U32.Max)
    Swag.require(Math.min(0_u64, Swag.U64.Max) == 0_u64)
    Swag.require(Math.max(0_u64, Swag.U64.Max) == Swag.U64.Max)
}

#test
{
    Swag.require(Math.isPowerOf2(1_u8))
    Swag.require(Math.isPowerOf2(128_u8))
    Swag.require(Math.isPowerOf2(0x80_u8))
    Swag.require(not Math.isPowerOf2(0_u8))
    Swag.require(not Math.isPowerOf2(127_u8))
    Swag.require(not Math.isPowerOf2(255_u8))

    Swag.require(Math.isPowerOf2(1_u16))
    Swag.require(Math.isPowerOf2(1024_u16))
    Swag.require(Math.isPowerOf2(0x8000_u16))
    Swag.require(not Math.isPowerOf2(0_u16))
    Swag.require(not Math.isPowerOf2(1023_u16))
    Swag.require(not Math.isPowerOf2(0xFFFF_u16))

    Swag.require(Math.isPowerOf2(1_u32))
    Swag.require(Math.isPowerOf2(1024_u32))
    Swag.require(Math.isPowerOf2(0x80000000_u32))
    Swag.require(not Math.isPowerOf2(0_u32))
    Swag.require(not Math.isPowerOf2(1023_u32))
    Swag.require(not Math.isPowerOf2(0xFFFFFFFF_u32))

    Swag.require(Math.isPowerOf2(1_u64))
    Swag.require(Math.isPowerOf2(1024_u64))
    Swag.require(Math.isPowerOf2(0x80000000_00000000_u64))
    Swag.require(not Math.isPowerOf2(0_u64))
    Swag.require(not Math.isPowerOf2(1023_u64))
    Swag.require(not Math.isPowerOf2(0xFFFFFFFF_FFFFFFFF_u64))
}

#test
{
    for value in 65536
    {
        let input = cast(u16, value)
        Swag.require(Math.hasZeroByte(input) == expectedHasZeroByte16(input))
    }

    for value in 256
    {
        let byte = cast(u8, value)
        Swag.require(Math.makeRepeat16(byte) == (cast(u16, byte) | (cast(u16, byte) << 8)))
        Swag.require(Math.hasByte(Math.makeRepeat16(byte), byte))
        Swag.require(Math.hasByte(cast(u16, byte), byte))
        Swag.require(Math.hasByte(cast(u16, byte) << 8, byte))

        if byte != 0xFF
        {
            let other = byte + 1
            Swag.require(not Math.hasByte(Math.makeRepeat16(byte), other))
        }
    }

    for value in 65536
    {
        let input = cast(u16, value)
        Swag.require(Math.hasByte(input, 0x00_u8) == expectedHasByte16(input, 0x00_u8))
        Swag.require(Math.hasByte(input, 0x7F_u8) == expectedHasByte16(input, 0x7F_u8))
        Swag.require(Math.hasByte(input, 0x80_u8) == expectedHasByte16(input, 0x80_u8))
        Swag.require(Math.hasByte(input, 0xFF_u8) == expectedHasByte16(input, 0xFF_u8))
    }
}

#test
{
    for value in 256
    {
        let byte  = cast(u8, value)
        let other = byte == 0 ? 1_u8 : byte == 0xFF ? 0xFE_u8 : ~byte

        for index in 4
        {
            let shift   = index * 8
            let value32 = (Math.makeRepeat32(other) & ~(0xFF_u32 << shift)) | (cast(u32, byte) << shift)
            Swag.require(Math.hasZeroByte(value32) == (byte == 0))
            Swag.require(Math.hasByte(value32, byte))
            Swag.require(not Math.hasByte(value32, byte ^ 0x80_u8))
        }

        for index in 8
        {
            let shift   = index * 8
            let value64 = (Math.makeRepeat64(other) & ~(0xFF_u64 << shift)) | (cast(u64, byte) << shift)
            Swag.require(Math.hasZeroByte(value64) == (byte == 0))
            Swag.require(Math.hasByte(value64, byte))
            Swag.require(not Math.hasByte(value64, byte ^ 0x80_u8))
        }
    }
}

#test
{
    Swag.require(Math.roundUpToPowerOf2(0_u32) == 1_u32)
    Swag.require(Math.roundUpToPowerOf2(1_u32) == 1_u32)
    Swag.require(Math.roundUpToPowerOf2(2_u32) == 2_u32)
    Swag.require(Math.roundUpToPowerOf2(3_u32) == 4_u32)
    Swag.require(Math.roundUpToPowerOf2(1024_u32) == 1024_u32)
    Swag.require(Math.roundUpToPowerOf2(1025_u32) == 2048_u32)
    Swag.require(Math.roundUpToPowerOf2(0x80000000_u32) == 0x80000000_u32)

    Swag.require(Math.roundUpToPowerOf2(0_u64) == 1_u64)
    Swag.require(Math.roundUpToPowerOf2(1_u64) == 1_u64)
    Swag.require(Math.roundUpToPowerOf2(2_u64) == 2_u64)
    Swag.require(Math.roundUpToPowerOf2(3_u64) == 4_u64)
    Swag.require(Math.roundUpToPowerOf2(1024_u64) == 1024_u64)
    Swag.require(Math.roundUpToPowerOf2(1025_u64) == 2048_u64)
    Swag.require(Math.roundUpToPowerOf2(0x80000000_00000000_u64) == 0x80000000_00000000_u64)

    Swag.require(Math.roundDownToPowerOf2(0_u32) == 0_u32)
    Swag.require(Math.roundDownToPowerOf2(1_u32) == 1_u32)
    Swag.require(Math.roundDownToPowerOf2(3_u32) == 2_u32)
    Swag.require(Math.roundDownToPowerOf2(1025_u32) == 1024_u32)
    Swag.require(Math.roundDownToPowerOf2(0xFFFFFFFF_u32) == 0x80000000_u32)
    Swag.require(Math.roundDownToPowerOf2(0_u64) == 0_u64)
    Swag.require(Math.roundDownToPowerOf2(1_u64) == 1_u64)
    Swag.require(Math.roundDownToPowerOf2(3_u64) == 2_u64)
    Swag.require(Math.roundDownToPowerOf2(1025_u64) == 1024_u64)
    Swag.require(Math.roundDownToPowerOf2(0xFFFFFFFF_FFFFFFFF_u64) == 0x80000000_00000000_u64)
}

#test
{
    Swag.require(Math.hasZeroByte(0x0000_u16))
    Swag.require(Math.hasZeroByte(0x0012_u16))
    Swag.require(Math.hasZeroByte(0x1200_u16))
    Swag.require(not Math.hasZeroByte(0x1212_u16))
    Swag.require(not Math.hasZeroByte(0xFFFF_u16))
    Swag.require(Math.hasZeroByte(0x00000000_u32))
    Swag.require(Math.hasZeroByte(0x00345678_u32))
    Swag.require(Math.hasZeroByte(0x12340078_u32))
    Swag.require(not Math.hasZeroByte(0x12345678_u32))
    Swag.require(not Math.hasZeroByte(0xFFFFFFFF_u32))
    Swag.require(Math.hasZeroByte(0x00000000_00000000_u64))
    Swag.require(Math.hasZeroByte(0x00345678_89ABCDEF_u64))
    Swag.require(Math.hasZeroByte(0x12345600_89ABCDEF_u64))
    Swag.require(not Math.hasZeroByte(0x12345678_89ABCDEF_u64))
    Swag.require(not Math.hasZeroByte(0xFFFFFFFF_FFFFFFFF_u64))

    Swag.require(Math.makeRepeat16(0x00_u8) == 0x0000_u16)
    Swag.require(Math.makeRepeat16(0x20_u8) == 0x2020_u16)
    Swag.require(Math.makeRepeat16(0xFF_u8) == 0xFFFF_u16)
    Swag.require(Math.makeRepeat32(0x00_u8) == 0x00000000_u32)
    Swag.require(Math.makeRepeat32(0x20_u8) == 0x20202020_u32)
    Swag.require(Math.makeRepeat32(0xFF_u8) == 0xFFFFFFFF_u32)
    Swag.require(Math.makeRepeat64(0x00_u8) == 0x00000000_00000000_u64)
    Swag.require(Math.makeRepeat64(0x20_u8) == 0x20202020_20202020_u64)
    Swag.require(Math.makeRepeat64(0xFF_u8) == 0xFFFFFFFF_FFFFFFFF_u64)
    Swag.require(Math.make16(0x12_u8, 0x34_u8) == 0x1234_u16)
    Swag.require(Math.make32(0x1234_u16, 0x5678_u16) == 0x12345678_u32)
    Swag.require(Math.make32(0x12_u8, 0x34_u8, 0x56_u8, 0x78_u8) == 0x12345678_u32)
    Swag.require(Math.make64(0x12345678_u32, 0x9ABCDEF0_u32) == 0x123456789ABCDEF0_u64)
    Swag.require(Math.make64(0_u32, 0xFFFFFFFF_u32) == 0x00000000FFFFFFFF_u64)
    Swag.require(Math.make64(0xFFFFFFFF_u32, 0_u32) == 0xFFFFFFFF00000000_u64)

    Swag.require(Math.hasByte(0x1234_u16, 0x12_u8))
    Swag.require(Math.hasByte(0x1234_u16, 0x34_u8))
    Swag.require(Math.hasByte(0x1200_u16, 0x00_u8))
    Swag.require(not Math.hasByte(0x1212_u16, 0x00_u8))
    Swag.require(not Math.hasByte(0x1234_u16, 0x56_u8))
    Swag.require(Math.hasByte(0x12345678_u32, 0x12_u8))
    Swag.require(Math.hasByte(0x12345678_u32, 0x56_u8))
    Swag.require(Math.hasByte(0x12345678_u32, 0x78_u8))
    Swag.require(not Math.hasByte(0x12345678_u32, 0x9A_u8))
    Swag.require(Math.hasByte(0x12345678_89ABCDEF_u64, 0x12_u8))
    Swag.require(Math.hasByte(0x12345678_89ABCDEF_u64, 0xAB_u8))
    Swag.require(Math.hasByte(0x12345678_89ABCDEF_u64, 0xEF_u8))
    Swag.require(not Math.hasByte(0x12345678_89ABCDEF_u64, 0x00_u8))
}

#test
{
    Swag.require(Math.sign(-5_s8) == -1_s8)
    Swag.require(Math.sign(0_s8) == 0_s8)
    Swag.require(Math.sign(5_s8) == 1_s8)
    Swag.require(Math.sign(-5_s16) == -1_s16)
    Swag.require(Math.sign(0_s16) == 0_s16)
    Swag.require(Math.sign(5_s16) == 1_s16)
    Swag.require(Math.sign(-5_s32) == -1_s32)
    Swag.require(Math.sign(0_s32) == 0_s32)
    Swag.require(Math.sign(5_s32) == 1_s32)
    Swag.require(Math.sign(-5_s64) == -1_s64)
    Swag.require(Math.sign(0_s64) == 0_s64)
    Swag.require(Math.sign(5_s64) == 1_s64)
}

#test
{
    for value in 256
    {
        let input = cast #bit (s8, cast(u8, value))
        Swag.require(Math.sign(input) == expectedSign8(input))
        if input != -128_s8
        {
            Swag.require(Math.abs(input) == expectedAbs8(input))
        }
    }

    for left in 256
    {
        let a = cast #bit (s8, cast(u8, left))
        for right in 256
        {
            let b = cast #bit (s8, cast(u8, right))
            Swag.require(Math.min(a, b) == (a < b ? a : b))
            Swag.require(Math.max(a, b) == (a > b ? a : b))
        }
    }

    for left in 256
    {
        let a = cast(u8, left)
        for right in 256
        {
            let b = cast(u8, right)
            Swag.require(Math.min(a, b) == (a < b ? a : b))
            Swag.require(Math.max(a, b) == (a > b ? a : b))
        }
    }
}

#test
{
    Swag.require(Math.min(-7_s8, 3_s8) == -7_s8)
    Swag.require(Math.max(-7_s8, 3_s8) == 3_s8)
    Swag.require(Math.min(-300_s16, 77_s16) == -300_s16)
    Swag.require(Math.max(-300_s16, 77_s16) == 77_s16)
    Swag.require(Math.min(-70000_s32, 300_s32) == -70000_s32)
    Swag.require(Math.max(-70000_s32, 300_s32) == 300_s32)
    Swag.require(Math.min(-5000000000_s64, 3_s64) == -5000000000_s64)
    Swag.require(Math.max(-5000000000_s64, 3_s64) == 3_s64)

    Swag.require(Math.min(7_u8, 3_u8) == 3_u8)
    Swag.require(Math.max(7_u8, 3_u8) == 7_u8)
    Swag.require(Math.min(700_u16, 30_u16) == 30_u16)
    Swag.require(Math.max(700_u16, 30_u16) == 700_u16)
    Swag.require(Math.min(70000_u32, 300_u32) == 300_u32)
    Swag.require(Math.max(70000_u32, 300_u32) == 70000_u32)
    Swag.require(Math.min(5000000000_u64, 3_u64) == 3_u64)
    Swag.require(Math.max(5000000000_u64, 3_u64) == 5000000000_u64)

    Swag.require(Math.abs(-7_s8) == 7_s8)
    Swag.require(Math.abs(0_s8) == 0_s8)
    Swag.require(Math.abs(-300_s16) == 300_s16)
    Swag.require(Math.abs(0_s16) == 0_s16)
    Swag.require(Math.abs(-70000_s32) == 70000_s32)
    Swag.require(Math.abs(0_s32) == 0_s32)
    Swag.require(Math.abs(-5000000000_s64) == 5000000000_s64)
    Swag.require(Math.abs(0_s64) == 0_s64)
}

#test
{
    Swag.require(expect Math.gcd(48, 18) == 6)
    Swag.require(expect Math.gcd(17, 0) == 17)
    Swag.require(expect Math.gcd(0, 17) == 17)
    Swag.require(expect Math.gcd(0, 0) == 0)
    Swag.require(expect Math.gcd(-48, 18) == 6)
    Swag.require(expect Math.gcd(48, -18) == 6)
    Swag.require(expect Math.gcd(-48, -18) == 6)
    Swag.require(expect Math.gcd(Swag.S64.Min, -1) == 1)
    Swag.require(expect Math.gcd(-1, Swag.S64.Min) == 1)
    Swag.require(expect Math.lcm(4, 6) == 12)
    Swag.require(expect Math.lcm(21, 6) == 42)
    Swag.require(expect Math.lcm(0, 6) == 0)
    Swag.require(expect Math.lcm(6, 0) == 0)
    Swag.require(expect Math.lcm(0, 0) == 0)
    Swag.require(expect Math.lcm(-4, 6) == 12)
    Swag.require(expect Math.lcm(4, -6) == 12)
    Swag.require(expect Math.lcm(-4, -6) == 12)
    Swag.require(expect Math.lcm(Swag.S64.Max, 1) == Swag.S64.Max)
    Swag.require(expect Math.lcm(Swag.S64.Max / 2, 2) == Swag.S64.Max - 1)

    var gcdOverflow: Swag.Error
    discard catch Math.gcd(Swag.S64.Min, 0) as gcdOverflow
    Swag.require(gcdOverflow.value() is Errors.OverflowError)

    var gcdOverflowReversed: Swag.Error
    discard catch Math.gcd(0, Swag.S64.Min) as gcdOverflowReversed
    Swag.require(gcdOverflowReversed.value() is Errors.OverflowError)

    var lcmOverflow: Swag.Error
    discard catch Math.lcm(Swag.S64.Min, 1) as lcmOverflow
    Swag.require(lcmOverflow.value() is Errors.OverflowError)

    var lcmOverflowProduct: Swag.Error
    discard catch Math.lcm(Swag.S64.Max, 2) as lcmOverflowProduct
    Swag.require(lcmOverflowProduct.value() is Errors.OverflowError)
}
