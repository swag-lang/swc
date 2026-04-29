#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    @assert(Math.isPowerOf2(1'u8))
    @assert(Math.isPowerOf2(128'u8))
    @assert(!Math.isPowerOf2(0'u8))
    @assert(!Math.isPowerOf2(127'u8))

    @assert(Math.isPowerOf2(1'u16))
    @assert(Math.isPowerOf2(1024'u16))
    @assert(!Math.isPowerOf2(0'u16))
    @assert(!Math.isPowerOf2(1023'u16))

    @assert(Math.isPowerOf2(1'u32))
    @assert(Math.isPowerOf2(1024'u32))
    @assert(!Math.isPowerOf2(0'u32))
    @assert(!Math.isPowerOf2(1023'u32))

    @assert(Math.isPowerOf2(1'u64))
    @assert(Math.isPowerOf2(1024'u64))
    @assert(!Math.isPowerOf2(0'u64))
    @assert(!Math.isPowerOf2(1023'u64))
}

#test
{
    @assert(Math.roundUpToPowerOf2(0'u32) == 1'u32)
    @assert(Math.roundUpToPowerOf2(1'u32) == 1'u32)
    @assert(Math.roundUpToPowerOf2(2'u32) == 2'u32)
    @assert(Math.roundUpToPowerOf2(3'u32) == 4'u32)
    @assert(Math.roundUpToPowerOf2(1024'u32) == 1024'u32)
    @assert(Math.roundUpToPowerOf2(1025'u32) == 2048'u32)

    @assert(Math.roundUpToPowerOf2(0'u64) == 1'u64)
    @assert(Math.roundUpToPowerOf2(1'u64) == 1'u64)
    @assert(Math.roundUpToPowerOf2(2'u64) == 2'u64)
    @assert(Math.roundUpToPowerOf2(3'u64) == 4'u64)
    @assert(Math.roundUpToPowerOf2(1024'u64) == 1024'u64)
    @assert(Math.roundUpToPowerOf2(1025'u64) == 2048'u64)

    @assert(Math.roundDownToPowerOf2(1'u32) == 1'u32)
    @assert(Math.roundDownToPowerOf2(3'u32) == 2'u32)
    @assert(Math.roundDownToPowerOf2(1025'u32) == 1024'u32)
    @assert(Math.roundDownToPowerOf2(1'u64) == 1'u64)
    @assert(Math.roundDownToPowerOf2(3'u64) == 2'u64)
    @assert(Math.roundDownToPowerOf2(1025'u64) == 1024'u64)
}

#test
{
    @assert(Math.hasZeroByte(0x1200'u16))
    @assert(!Math.hasZeroByte(0x1212'u16))
    @assert(Math.hasZeroByte(0x12340078'u32))
    @assert(!Math.hasZeroByte(0x12345678'u32))
    @assert(Math.hasZeroByte(0x12345600_89abcdef'u64))
    @assert(!Math.hasZeroByte(0x12345678_89abcdef'u64))

    @assert(Math.makeRepeat16(0x20'u8) == 0x2020'u16)
    @assert(Math.makeRepeat32(0x20'u8) == 0x20202020'u32)
    @assert(Math.makeRepeat64(0x20'u8) == 0x20202020_20202020'u64)
    @assert(Math.make64(0x12345678'u32, 0x9abcdef0'u32) == 0x123456789abcdef0'u64)

    @assert(Math.hasByte(0x1234'u16, 0x12'u8))
    @assert(Math.hasByte(0x1200'u16, 0x00'u8))
    @assert(!Math.hasByte(0x1212'u16, 0x00'u8))
    @assert(!Math.hasByte(0x1234'u16, 0x56'u8))
    @assert(Math.hasByte(0x12345678'u32, 0x56'u8))
    @assert(!Math.hasByte(0x12345678'u32, 0x9a'u8))
    @assert(Math.hasByte(0x12345678_89abcdef'u64, 0xab'u8))
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
    @assert(Math.lcm(4, 6) == 12)
    @assert(Math.lcm(21, 6) == 42)
}
