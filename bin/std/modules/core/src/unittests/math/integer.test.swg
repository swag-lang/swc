#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func expectedHasZeroByte16(value: u16)->bool
{
    return (value & 0x00ff) == 0 or (value & 0xff00) == 0
}

func expectedHasByte16(value: u16, byte: u8)->bool
{
    let expected = cast(u16) byte
    return (value & 0x00ff) == expected or ((value >> 8) & 0x00ff) == expected
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
    @assert(Math.isPowerOf2(1'u8))
    @assert(Math.isPowerOf2(128'u8))
    @assert(Math.isPowerOf2(0x80'u8))
    @assert(!Math.isPowerOf2(0'u8))
    @assert(!Math.isPowerOf2(127'u8))
    @assert(!Math.isPowerOf2(255'u8))

    @assert(Math.isPowerOf2(1'u16))
    @assert(Math.isPowerOf2(1024'u16))
    @assert(Math.isPowerOf2(0x8000'u16))
    @assert(!Math.isPowerOf2(0'u16))
    @assert(!Math.isPowerOf2(1023'u16))
    @assert(!Math.isPowerOf2(0xffff'u16))

    @assert(Math.isPowerOf2(1'u32))
    @assert(Math.isPowerOf2(1024'u32))
    @assert(Math.isPowerOf2(0x80000000'u32))
    @assert(!Math.isPowerOf2(0'u32))
    @assert(!Math.isPowerOf2(1023'u32))
    @assert(!Math.isPowerOf2(0xffffffff'u32))

    @assert(Math.isPowerOf2(1'u64))
    @assert(Math.isPowerOf2(1024'u64))
    @assert(Math.isPowerOf2(0x80000000_00000000'u64))
    @assert(!Math.isPowerOf2(0'u64))
    @assert(!Math.isPowerOf2(1023'u64))
    @assert(!Math.isPowerOf2(0xffffffff_ffffffff'u64))
}

#test
{
    for value in 65536
    {
        let input = cast(u16) value
        @assert(Math.hasZeroByte(input) == expectedHasZeroByte16(input))
    }

    for value in 256
    {
        let byte = cast(u8) value
        @assert(Math.makeRepeat16(byte) == (cast(u16) byte | (cast(u16) byte << 8)))
        @assert(Math.hasByte(Math.makeRepeat16(byte), byte))
        @assert(Math.hasByte(cast(u16) byte, byte))
        @assert(Math.hasByte(cast(u16) byte << 8, byte))

        if byte != 0xff
        {
            let other = byte + 1
            @assert(!Math.hasByte(Math.makeRepeat16(byte), other))
        }
    }

    for value in 65536
    {
        let input = cast(u16) value
        @assert(Math.hasByte(input, 0x00'u8) == expectedHasByte16(input, 0x00'u8))
        @assert(Math.hasByte(input, 0x7f'u8) == expectedHasByte16(input, 0x7f'u8))
        @assert(Math.hasByte(input, 0x80'u8) == expectedHasByte16(input, 0x80'u8))
        @assert(Math.hasByte(input, 0xff'u8) == expectedHasByte16(input, 0xff'u8))
    }
}

#test
{
    @assert(Math.roundUpToPowerOf2(0'u32) == 1'u32)
    @assert(Math.roundUpToPowerOf2(1'u32) == 1'u32)
    @assert(Math.roundUpToPowerOf2(2'u32) == 2'u32)
    @assert(Math.roundUpToPowerOf2(3'u32) == 4'u32)
    @assert(Math.roundUpToPowerOf2(1024'u32) == 1024'u32)
    @assert(Math.roundUpToPowerOf2(1025'u32) == 2048'u32)
    @assert(Math.roundUpToPowerOf2(0x80000000'u32) == 0x80000000'u32)

    @assert(Math.roundUpToPowerOf2(0'u64) == 1'u64)
    @assert(Math.roundUpToPowerOf2(1'u64) == 1'u64)
    @assert(Math.roundUpToPowerOf2(2'u64) == 2'u64)
    @assert(Math.roundUpToPowerOf2(3'u64) == 4'u64)
    @assert(Math.roundUpToPowerOf2(1024'u64) == 1024'u64)
    @assert(Math.roundUpToPowerOf2(1025'u64) == 2048'u64)
    @assert(Math.roundUpToPowerOf2(0x80000000_00000000'u64) == 0x80000000_00000000'u64)

    @assert(Math.roundDownToPowerOf2(0'u32) == 0'u32)
    @assert(Math.roundDownToPowerOf2(1'u32) == 1'u32)
    @assert(Math.roundDownToPowerOf2(3'u32) == 2'u32)
    @assert(Math.roundDownToPowerOf2(1025'u32) == 1024'u32)
    @assert(Math.roundDownToPowerOf2(0xffffffff'u32) == 0x80000000'u32)
    @assert(Math.roundDownToPowerOf2(0'u64) == 0'u64)
    @assert(Math.roundDownToPowerOf2(1'u64) == 1'u64)
    @assert(Math.roundDownToPowerOf2(3'u64) == 2'u64)
    @assert(Math.roundDownToPowerOf2(1025'u64) == 1024'u64)
    @assert(Math.roundDownToPowerOf2(0xffffffff_ffffffff'u64) == 0x80000000_00000000'u64)
}

#test
{
    @assert(Math.hasZeroByte(0x0000'u16))
    @assert(Math.hasZeroByte(0x0012'u16))
    @assert(Math.hasZeroByte(0x1200'u16))
    @assert(!Math.hasZeroByte(0x1212'u16))
    @assert(!Math.hasZeroByte(0xffff'u16))
    @assert(Math.hasZeroByte(0x00000000'u32))
    @assert(Math.hasZeroByte(0x00345678'u32))
    @assert(Math.hasZeroByte(0x12340078'u32))
    @assert(!Math.hasZeroByte(0x12345678'u32))
    @assert(!Math.hasZeroByte(0xffffffff'u32))
    @assert(Math.hasZeroByte(0x00000000_00000000'u64))
    @assert(Math.hasZeroByte(0x00345678_89abcdef'u64))
    @assert(Math.hasZeroByte(0x12345600_89abcdef'u64))
    @assert(!Math.hasZeroByte(0x12345678_89abcdef'u64))
    @assert(!Math.hasZeroByte(0xffffffff_ffffffff'u64))

    @assert(Math.makeRepeat16(0x00'u8) == 0x0000'u16)
    @assert(Math.makeRepeat16(0x20'u8) == 0x2020'u16)
    @assert(Math.makeRepeat16(0xff'u8) == 0xffff'u16)
    @assert(Math.makeRepeat32(0x00'u8) == 0x00000000'u32)
    @assert(Math.makeRepeat32(0x20'u8) == 0x20202020'u32)
    @assert(Math.makeRepeat32(0xff'u8) == 0xffffffff'u32)
    @assert(Math.makeRepeat64(0x00'u8) == 0x00000000_00000000'u64)
    @assert(Math.makeRepeat64(0x20'u8) == 0x20202020_20202020'u64)
    @assert(Math.makeRepeat64(0xff'u8) == 0xffffffff_ffffffff'u64)
    @assert(Math.make64(0x12345678'u32, 0x9abcdef0'u32) == 0x123456789abcdef0'u64)
    @assert(Math.make64(0'u32, 0xffffffff'u32) == 0x00000000ffffffff'u64)
    @assert(Math.make64(0xffffffff'u32, 0'u32) == 0xffffffff00000000'u64)

    @assert(Math.hasByte(0x1234'u16, 0x12'u8))
    @assert(Math.hasByte(0x1234'u16, 0x34'u8))
    @assert(Math.hasByte(0x1200'u16, 0x00'u8))
    @assert(!Math.hasByte(0x1212'u16, 0x00'u8))
    @assert(!Math.hasByte(0x1234'u16, 0x56'u8))
    @assert(Math.hasByte(0x12345678'u32, 0x12'u8))
    @assert(Math.hasByte(0x12345678'u32, 0x56'u8))
    @assert(Math.hasByte(0x12345678'u32, 0x78'u8))
    @assert(!Math.hasByte(0x12345678'u32, 0x9a'u8))
    @assert(Math.hasByte(0x12345678_89abcdef'u64, 0x12'u8))
    @assert(Math.hasByte(0x12345678_89abcdef'u64, 0xab'u8))
    @assert(Math.hasByte(0x12345678_89abcdef'u64, 0xef'u8))
    @assert(!Math.hasByte(0x12345678_89abcdef'u64, 0x00'u8))
}

#test
{
    @assert(Math.sign(-5's8) == -1's8)
    @assert(Math.sign(0's8) == 0's8)
    @assert(Math.sign(5's8) == 1's8)
    @assert(Math.sign(-5's16) == -1's16)
    @assert(Math.sign(0's16) == 0's16)
    @assert(Math.sign(5's16) == 1's16)
    @assert(Math.sign(-5's32) == -1's32)
    @assert(Math.sign(0's32) == 0's32)
    @assert(Math.sign(5's32) == 1's32)
    @assert(Math.sign(-5's64) == -1's64)
    @assert(Math.sign(0's64) == 0's64)
    @assert(Math.sign(5's64) == 1's64)
}

#test
{
    for value in 256
    {
        let input = cast #bit (s8) cast(u8) value
        @assert(Math.sign(input) == expectedSign8(input))
        if input != -128's8 do
            @assert(Math.abs(input) == expectedAbs8(input))
    }

    for left in 256
    {
        let a = cast #bit (s8) cast(u8) left
        for right in 256
        {
            let b = cast #bit (s8) cast(u8) right
            @assert(Math.min(a, b) == (a < b ? a : b))
            @assert(Math.max(a, b) == (a > b ? a : b))
        }
    }

    for left in 256
    {
        let a = cast(u8) left
        for right in 256
        {
            let b = cast(u8) right
            @assert(Math.min(a, b) == (a < b ? a : b))
            @assert(Math.max(a, b) == (a > b ? a : b))
        }
    }
}

#test
{
    @assert(Math.min(-7's8, 3's8) == -7's8)
    @assert(Math.max(-7's8, 3's8) == 3's8)
    @assert(Math.min(-300's16, 77's16) == -300's16)
    @assert(Math.max(-300's16, 77's16) == 77's16)
    @assert(Math.min(-70000's32, 300's32) == -70000's32)
    @assert(Math.max(-70000's32, 300's32) == 300's32)
    @assert(Math.min(-5000000000's64, 3's64) == -5000000000's64)
    @assert(Math.max(-5000000000's64, 3's64) == 3's64)

    @assert(Math.min(7'u8, 3'u8) == 3'u8)
    @assert(Math.max(7'u8, 3'u8) == 7'u8)
    @assert(Math.min(700'u16, 30'u16) == 30'u16)
    @assert(Math.max(700'u16, 30'u16) == 700'u16)
    @assert(Math.min(70000'u32, 300'u32) == 300'u32)
    @assert(Math.max(70000'u32, 300'u32) == 70000'u32)
    @assert(Math.min(5000000000'u64, 3'u64) == 3'u64)
    @assert(Math.max(5000000000'u64, 3'u64) == 5000000000'u64)

    @assert(Math.abs(-7's8) == 7's8)
    @assert(Math.abs(0's8) == 0's8)
    @assert(Math.abs(-300's16) == 300's16)
    @assert(Math.abs(0's16) == 0's16)
    @assert(Math.abs(-70000's32) == 70000's32)
    @assert(Math.abs(0's32) == 0's32)
    @assert(Math.abs(-5000000000's64) == 5000000000's64)
    @assert(Math.abs(0's64) == 0's64)
}

#test
{
    @assert(Math.gcd(48, 18) == 6)
    @assert(Math.gcd(17, 0) == 17)
    @assert(Math.gcd(0, 17) == 17)
    @assert(Math.gcd(0, 0) == 0)
    @assert(Math.gcd(-48, 18) == 6)
    @assert(Math.gcd(48, -18) == 6)
    @assert(Math.gcd(-48, -18) == 6)
    @assert(Math.lcm(4, 6) == 12)
    @assert(Math.lcm(21, 6) == 42)
    @assert(Math.lcm(0, 6) == 0)
    @assert(Math.lcm(6, 0) == 0)
    @assert(Math.lcm(0, 0) == 0)
    @assert(Math.lcm(-4, 6) == 12)
    @assert(Math.lcm(4, -6) == 12)
    @assert(Math.lcm(-4, -6) == 12)
}
