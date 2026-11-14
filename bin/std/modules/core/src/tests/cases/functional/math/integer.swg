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
    if value < 0 do
        return -1
    if value > 0 do
        return 1
    return 0
}

func expectedAbs8(value: s8)->s8
{
    if value < 0 do
        return -value
    return value
}

#test
{
    Swag.require(Math.byteAt(0xA5'u8, 0) == 0xA5'u8)

    Swag.require(Math.byteAt(0x1234'u16, 0) == 0x34'u8)
    Swag.require(Math.byteAt(0x1234'u16, 1) == 0x12'u8)

    Swag.require(Math.byteAt(0x12345678'u32, 0) == 0x78'u8)
    Swag.require(Math.byteAt(0x12345678'u32, 1) == 0x56'u8)
    Swag.require(Math.byteAt(0x12345678'u32, 2) == 0x34'u8)
    Swag.require(Math.byteAt(0x12345678'u32, 3) == 0x12'u8)

    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 0) == 0xEF'u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 1) == 0xCD'u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 2) == 0xAB'u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 3) == 0x89'u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 4) == 0x67'u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 5) == 0x45'u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 6) == 0x23'u8)
    Swag.require(Math.byteAt(0x01234567_89ABCDEF'u64, 7) == 0x01'u8)
}

#test
{
    Swag.require(Math.sign(Swag.S8.Min) == -1's8)
    Swag.require(Math.sign(Swag.S8.Max) == 1's8)
    Swag.require(Math.min(Swag.S8.Min, Swag.S8.Max) == Swag.S8.Min)
    Swag.require(Math.max(Swag.S8.Min, Swag.S8.Max) == Swag.S8.Max)

    Swag.require(Math.sign(Swag.S16.Min) == -1's16)
    Swag.require(Math.sign(Swag.S16.Max) == 1's16)
    Swag.require(Math.min(Swag.S16.Min, Swag.S16.Max) == Swag.S16.Min)
    Swag.require(Math.max(Swag.S16.Min, Swag.S16.Max) == Swag.S16.Max)

    Swag.require(Math.sign(Swag.S32.Min) == -1's32)
    Swag.require(Math.sign(Swag.S32.Max) == 1's32)
    Swag.require(Math.min(Swag.S32.Min, Swag.S32.Max) == Swag.S32.Min)
    Swag.require(Math.max(Swag.S32.Min, Swag.S32.Max) == Swag.S32.Max)

    Swag.require(Math.sign(Swag.S64.Min) == -1's64)
    Swag.require(Math.sign(Swag.S64.Max) == 1's64)
    Swag.require(Math.min(Swag.S64.Min, Swag.S64.Max) == Swag.S64.Min)
    Swag.require(Math.max(Swag.S64.Min, Swag.S64.Max) == Swag.S64.Max)

    Swag.require(Math.min(0'u8, Swag.U8.Max) == 0'u8)
    Swag.require(Math.max(0'u8, Swag.U8.Max) == Swag.U8.Max)
    Swag.require(Math.min(0'u16, Swag.U16.Max) == 0'u16)
    Swag.require(Math.max(0'u16, Swag.U16.Max) == Swag.U16.Max)
    Swag.require(Math.min(0'u32, Swag.U32.Max) == 0'u32)
    Swag.require(Math.max(0'u32, Swag.U32.Max) == Swag.U32.Max)
    Swag.require(Math.min(0'u64, Swag.U64.Max) == 0'u64)
    Swag.require(Math.max(0'u64, Swag.U64.Max) == Swag.U64.Max)
}

#test
{
    Swag.require(Math.isPowerOf2(1'u8))
    Swag.require(Math.isPowerOf2(128'u8))
    Swag.require(Math.isPowerOf2(0x80'u8))
    Swag.require(not Math.isPowerOf2(0'u8))
    Swag.require(not Math.isPowerOf2(127'u8))
    Swag.require(not Math.isPowerOf2(255'u8))

    Swag.require(Math.isPowerOf2(1'u16))
    Swag.require(Math.isPowerOf2(1024'u16))
    Swag.require(Math.isPowerOf2(0x8000'u16))
    Swag.require(not Math.isPowerOf2(0'u16))
    Swag.require(not Math.isPowerOf2(1023'u16))
    Swag.require(not Math.isPowerOf2(0xFFFF'u16))

    Swag.require(Math.isPowerOf2(1'u32))
    Swag.require(Math.isPowerOf2(1024'u32))
    Swag.require(Math.isPowerOf2(0x80000000'u32))
    Swag.require(not Math.isPowerOf2(0'u32))
    Swag.require(not Math.isPowerOf2(1023'u32))
    Swag.require(not Math.isPowerOf2(0xFFFFFFFF'u32))

    Swag.require(Math.isPowerOf2(1'u64))
    Swag.require(Math.isPowerOf2(1024'u64))
    Swag.require(Math.isPowerOf2(0x80000000_00000000'u64))
    Swag.require(not Math.isPowerOf2(0'u64))
    Swag.require(not Math.isPowerOf2(1023'u64))
    Swag.require(not Math.isPowerOf2(0xFFFFFFFF_FFFFFFFF'u64))
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
        Swag.require(Math.hasByte(input, 0x00'u8) == expectedHasByte16(input, 0x00'u8))
        Swag.require(Math.hasByte(input, 0x7F'u8) == expectedHasByte16(input, 0x7F'u8))
        Swag.require(Math.hasByte(input, 0x80'u8) == expectedHasByte16(input, 0x80'u8))
        Swag.require(Math.hasByte(input, 0xFF'u8) == expectedHasByte16(input, 0xFF'u8))
    }
}

#test
{
    for value in 256
    {
        let byte  = cast(u8, value)
        let other = byte == 0 ? 1'u8 : byte == 0xFF ? 0xFE'u8 : ~byte

        for index in 4
        {
            let shift   = index * 8
            let value32 = (Math.makeRepeat32(other) & ~(0xFF'u32 << shift)) | (cast(u32, byte) << shift)
            Swag.require(Math.hasZeroByte(value32) == (byte == 0))
            Swag.require(Math.hasByte(value32, byte))
            Swag.require(not Math.hasByte(value32, byte ^ 0x80'u8))
        }

        for index in 8
        {
            let shift   = index * 8
            let value64 = (Math.makeRepeat64(other) & ~(0xFF'u64 << shift)) | (cast(u64, byte) << shift)
            Swag.require(Math.hasZeroByte(value64) == (byte == 0))
            Swag.require(Math.hasByte(value64, byte))
            Swag.require(not Math.hasByte(value64, byte ^ 0x80'u8))
        }
    }
}

#test
{
    Swag.require(Math.roundUpToPowerOf2(0'u32) == 1'u32)
    Swag.require(Math.roundUpToPowerOf2(1'u32) == 1'u32)
    Swag.require(Math.roundUpToPowerOf2(2'u32) == 2'u32)
    Swag.require(Math.roundUpToPowerOf2(3'u32) == 4'u32)
    Swag.require(Math.roundUpToPowerOf2(1024'u32) == 1024'u32)
    Swag.require(Math.roundUpToPowerOf2(1025'u32) == 2048'u32)
    Swag.require(Math.roundUpToPowerOf2(0x80000000'u32) == 0x80000000'u32)

    Swag.require(Math.roundUpToPowerOf2(0'u64) == 1'u64)
    Swag.require(Math.roundUpToPowerOf2(1'u64) == 1'u64)
    Swag.require(Math.roundUpToPowerOf2(2'u64) == 2'u64)
    Swag.require(Math.roundUpToPowerOf2(3'u64) == 4'u64)
    Swag.require(Math.roundUpToPowerOf2(1024'u64) == 1024'u64)
    Swag.require(Math.roundUpToPowerOf2(1025'u64) == 2048'u64)
    Swag.require(Math.roundUpToPowerOf2(0x80000000_00000000'u64) == 0x80000000_00000000'u64)

    Swag.require(Math.roundDownToPowerOf2(0'u32) == 0'u32)
    Swag.require(Math.roundDownToPowerOf2(1'u32) == 1'u32)
    Swag.require(Math.roundDownToPowerOf2(3'u32) == 2'u32)
    Swag.require(Math.roundDownToPowerOf2(1025'u32) == 1024'u32)
    Swag.require(Math.roundDownToPowerOf2(0xFFFFFFFF'u32) == 0x80000000'u32)
    Swag.require(Math.roundDownToPowerOf2(0'u64) == 0'u64)
    Swag.require(Math.roundDownToPowerOf2(1'u64) == 1'u64)
    Swag.require(Math.roundDownToPowerOf2(3'u64) == 2'u64)
    Swag.require(Math.roundDownToPowerOf2(1025'u64) == 1024'u64)
    Swag.require(Math.roundDownToPowerOf2(0xFFFFFFFF_FFFFFFFF'u64) == 0x80000000_00000000'u64)
}

#test
{
    Swag.require(Math.hasZeroByte(0x0000'u16))
    Swag.require(Math.hasZeroByte(0x0012'u16))
    Swag.require(Math.hasZeroByte(0x1200'u16))
    Swag.require(not Math.hasZeroByte(0x1212'u16))
    Swag.require(not Math.hasZeroByte(0xFFFF'u16))
    Swag.require(Math.hasZeroByte(0x00000000'u32))
    Swag.require(Math.hasZeroByte(0x00345678'u32))
    Swag.require(Math.hasZeroByte(0x12340078'u32))
    Swag.require(not Math.hasZeroByte(0x12345678'u32))
    Swag.require(not Math.hasZeroByte(0xFFFFFFFF'u32))
    Swag.require(Math.hasZeroByte(0x00000000_00000000'u64))
    Swag.require(Math.hasZeroByte(0x00345678_89ABCDEF'u64))
    Swag.require(Math.hasZeroByte(0x12345600_89ABCDEF'u64))
    Swag.require(not Math.hasZeroByte(0x12345678_89ABCDEF'u64))
    Swag.require(not Math.hasZeroByte(0xFFFFFFFF_FFFFFFFF'u64))

    Swag.require(Math.makeRepeat16(0x00'u8) == 0x0000'u16)
    Swag.require(Math.makeRepeat16(0x20'u8) == 0x2020'u16)
    Swag.require(Math.makeRepeat16(0xFF'u8) == 0xFFFF'u16)
    Swag.require(Math.makeRepeat32(0x00'u8) == 0x00000000'u32)
    Swag.require(Math.makeRepeat32(0x20'u8) == 0x20202020'u32)
    Swag.require(Math.makeRepeat32(0xFF'u8) == 0xFFFFFFFF'u32)
    Swag.require(Math.makeRepeat64(0x00'u8) == 0x00000000_00000000'u64)
    Swag.require(Math.makeRepeat64(0x20'u8) == 0x20202020_20202020'u64)
    Swag.require(Math.makeRepeat64(0xFF'u8) == 0xFFFFFFFF_FFFFFFFF'u64)
    Swag.require(Math.make16(0x12'u8, 0x34'u8) == 0x1234'u16)
    Swag.require(Math.make32(0x1234'u16, 0x5678'u16) == 0x12345678'u32)
    Swag.require(Math.make32(0x12'u8, 0x34'u8, 0x56'u8, 0x78'u8) == 0x12345678'u32)
    Swag.require(Math.make64(0x12345678'u32, 0x9ABCDEF0'u32) == 0x123456789ABCDEF0'u64)
    Swag.require(Math.make64(0'u32, 0xFFFFFFFF'u32) == 0x00000000FFFFFFFF'u64)
    Swag.require(Math.make64(0xFFFFFFFF'u32, 0'u32) == 0xFFFFFFFF00000000'u64)

    Swag.require(Math.hasByte(0x1234'u16, 0x12'u8))
    Swag.require(Math.hasByte(0x1234'u16, 0x34'u8))
    Swag.require(Math.hasByte(0x1200'u16, 0x00'u8))
    Swag.require(not Math.hasByte(0x1212'u16, 0x00'u8))
    Swag.require(not Math.hasByte(0x1234'u16, 0x56'u8))
    Swag.require(Math.hasByte(0x12345678'u32, 0x12'u8))
    Swag.require(Math.hasByte(0x12345678'u32, 0x56'u8))
    Swag.require(Math.hasByte(0x12345678'u32, 0x78'u8))
    Swag.require(not Math.hasByte(0x12345678'u32, 0x9A'u8))
    Swag.require(Math.hasByte(0x12345678_89ABCDEF'u64, 0x12'u8))
    Swag.require(Math.hasByte(0x12345678_89ABCDEF'u64, 0xAB'u8))
    Swag.require(Math.hasByte(0x12345678_89ABCDEF'u64, 0xEF'u8))
    Swag.require(not Math.hasByte(0x12345678_89ABCDEF'u64, 0x00'u8))
}

#test
{
    Swag.require(Math.sign(-5's8) == -1's8)
    Swag.require(Math.sign(0's8) == 0's8)
    Swag.require(Math.sign(5's8) == 1's8)
    Swag.require(Math.sign(-5's16) == -1's16)
    Swag.require(Math.sign(0's16) == 0's16)
    Swag.require(Math.sign(5's16) == 1's16)
    Swag.require(Math.sign(-5's32) == -1's32)
    Swag.require(Math.sign(0's32) == 0's32)
    Swag.require(Math.sign(5's32) == 1's32)
    Swag.require(Math.sign(-5's64) == -1's64)
    Swag.require(Math.sign(0's64) == 0's64)
    Swag.require(Math.sign(5's64) == 1's64)
}

#test
{
    for value in 256
    {
        let input = cast #bit (s8, cast(u8, value))
        Swag.require(Math.sign(input) == expectedSign8(input))
        if input != -128's8 do
            Swag.require(Math.abs(input) == expectedAbs8(input))
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
    Swag.require(Math.min(-7's8, 3's8) == -7's8)
    Swag.require(Math.max(-7's8, 3's8) == 3's8)
    Swag.require(Math.min(-300's16, 77's16) == -300's16)
    Swag.require(Math.max(-300's16, 77's16) == 77's16)
    Swag.require(Math.min(-70000's32, 300's32) == -70000's32)
    Swag.require(Math.max(-70000's32, 300's32) == 300's32)
    Swag.require(Math.min(-5000000000's64, 3's64) == -5000000000's64)
    Swag.require(Math.max(-5000000000's64, 3's64) == 3's64)

    Swag.require(Math.min(7'u8, 3'u8) == 3'u8)
    Swag.require(Math.max(7'u8, 3'u8) == 7'u8)
    Swag.require(Math.min(700'u16, 30'u16) == 30'u16)
    Swag.require(Math.max(700'u16, 30'u16) == 700'u16)
    Swag.require(Math.min(70000'u32, 300'u32) == 300'u32)
    Swag.require(Math.max(70000'u32, 300'u32) == 70000'u32)
    Swag.require(Math.min(5000000000'u64, 3'u64) == 3'u64)
    Swag.require(Math.max(5000000000'u64, 3'u64) == 5000000000'u64)

    Swag.require(Math.abs(-7's8) == 7's8)
    Swag.require(Math.abs(0's8) == 0's8)
    Swag.require(Math.abs(-300's16) == 300's16)
    Swag.require(Math.abs(0's16) == 0's16)
    Swag.require(Math.abs(-70000's32) == 70000's32)
    Swag.require(Math.abs(0's32) == 0's32)
    Swag.require(Math.abs(-5000000000's64) == 5000000000's64)
    Swag.require(Math.abs(0's64) == 0's64)
}

#test
{
    Swag.require(Math.gcd(48, 18) == 6)
    Swag.require(Math.gcd(17, 0) == 17)
    Swag.require(Math.gcd(0, 17) == 17)
    Swag.require(Math.gcd(0, 0) == 0)
    Swag.require(Math.gcd(-48, 18) == 6)
    Swag.require(Math.gcd(48, -18) == 6)
    Swag.require(Math.gcd(-48, -18) == 6)
    Swag.require(Math.gcd(Swag.S64.Min, -1) == 1)
    Swag.require(Math.gcd(-1, Swag.S64.Min) == 1)
    Swag.require(Math.lcm(4, 6) == 12)
    Swag.require(Math.lcm(21, 6) == 42)
    Swag.require(Math.lcm(0, 6) == 0)
    Swag.require(Math.lcm(6, 0) == 0)
    Swag.require(Math.lcm(0, 0) == 0)
    Swag.require(Math.lcm(-4, 6) == 12)
    Swag.require(Math.lcm(4, -6) == 12)
    Swag.require(Math.lcm(-4, -6) == 12)
}
