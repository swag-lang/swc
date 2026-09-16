#global private

#[Swag.NoInline]
func byteShift(a: u64)->u64 => (a << 8) & 0xFF00

#[Swag.NoInline]
func wordShift(a: u64)->u64 => (a << 8) & 0xFFFF00

#[Swag.NoInline]
func topByte(a: u64)->u64 => (a << 56) & 0xFF00000000000000

#[Swag.NoInline]
func middleDword(a: u64)->u64 => (a << 16) & 0xFFFFFFFF0000

#[Swag.NoInline]
func byteShift32(a: u32)->u32 => (a << 8) & 0xFF00

#[Swag.NoInline]
func extraLowBits(a: u64)->u64 => (a << 8) & 0xFF7F

#[Swag.NoInline]
func reusedShift(a: u64)->u64
{
    let shifted = a << 8
    return (shifted & 0xFF00) ^ (shifted >> 32)
}

#[Swag.NoInline]
func maskedBranch(a: u64)->s32
{
    if ((a << 8) & 0xFFFF00) == 0 do
        return 11
    return 27
}

#test
{
    let values = [0'u64, 1, 255, 256, 65535, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x0123456789ABCDEF]
    for a in values
    {
        Swag.assert(byteShift(a) == ((a & 255) << 8))
        Swag.assert(wordShift(a) == ((a & 65535) << 8))
        Swag.assert(topByte(a) == ((a & 255) << 56))
        Swag.assert(middleDword(a) == ((a & 0xFFFFFFFF) << 16))
        let a32 = cast(u32) (a & 0xFFFFFFFF)
        Swag.assert(byteShift32(a32) == ((a32 & 255) << 8))
        Swag.assert(extraLowBits(a) == ((a & 255) << 8))
        Swag.assert(reusedShift(a) == (((a & 255) << 8) ^ ((a & 0xFFFFFFFFFFFFFF) >> 24)))
        Swag.assert(maskedBranch(a) == ((a & 65535) == 0 ? 11 : 27))
    }
}
