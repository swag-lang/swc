#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func bit0(a, b: u64)->u64 => ((a >> 0) & 1) * b

#[Swag.NoInline]
func bit1(a, b: u64)->u64 => ((a >> 1) & 1) * b

#[Swag.NoInline]
func bit7(a, b: u64)->u64 => ((a >> 7) & 1) * b

#[Swag.NoInline]
func bit8(a, b: u64)->u64 => ((a >> 8) & 1) * b

#[Swag.NoInline]
func bit15(a, b: u64)->u64 => ((a >> 15) & 1) * b

#[Swag.NoInline]
func bit16(a, b: u64)->u64 => ((a >> 16) & 1) * b

#[Swag.NoInline]
func bit17(a, b: u64)->u64 => ((a >> 17) & 1) * b

#[Swag.NoInline]
func bit31(a, b: u64)->u64 => ((a >> 31) & 1) * b

#[Swag.NoInline]
func bit32(a, b: u64)->u64 => ((a >> 32) & 1) * b

#[Swag.NoInline]
func bit40(a, b: u64)->u64 => ((a >> 40) & 1) * b

#[Swag.NoInline]
func bit63(a, b: u64)->u64 => ((a >> 63) & 1) * b

#[Swag.NoInline]
func shared(a, b: u64)->u64
{
    let shifted = a >> 17
    return ((shifted & 1) * b) ^ shifted
}

#[Swag.NoInline]
func narrow7(a, b: u32)->u32 => ((a >> 7) & 1) * b

#[Swag.NoInline]
func narrow15(a, b: u32)->u32 => ((a >> 15) & 1) * b

#[Swag.NoInline]
func narrow31(a, b: u32)->u32 => ((a >> 31) & 1) * b

#[Swag.NoInline]
func signedBit(a, b: s64)->s64 => ((a >> 17) & 1) * b

#[Swag.NoInline]
func widenedBit(a: u32, b: u64)->u64 => cast(u64) ((a >> 31) & 1) * b

#test
{
    let values = [0'u64, 1, 2, 0xFF, 0x100, 0x8000, 0x20000, 0x80000000, 0x100000000, 0x10000000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(bit0(a, b) == ((a & 0x1) != 0 ? b : 0))
            Swag.assert(bit1(a, b) == ((a & 0x2) != 0 ? b : 0))
            Swag.assert(bit7(a, b) == ((a & 0x80) != 0 ? b : 0))
            Swag.assert(bit8(a, b) == ((a & 0x100) != 0 ? b : 0))
            Swag.assert(bit15(a, b) == ((a & 0x8000) != 0 ? b : 0))
            Swag.assert(bit16(a, b) == ((a & 0x10000) != 0 ? b : 0))
            Swag.assert(bit17(a, b) == ((a & 0x20000) != 0 ? b : 0))
            Swag.assert(bit31(a, b) == ((a & 0x80000000) != 0 ? b : 0))
            Swag.assert(bit32(a, b) == ((a & 0x100000000) != 0 ? b : 0))
            Swag.assert(bit40(a, b) == ((a & 0x10000000000) != 0 ? b : 0))
            Swag.assert(bit63(a, b) == ((a & 0x8000000000000000) != 0 ? b : 0))
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(narrow7(lowA, lowB) == ((lowA & 0x80) != 0 ? lowB : 0))
            Swag.assert(narrow15(lowA, lowB) == ((lowA & 0x8000) != 0 ? lowB : 0))
            Swag.assert(narrow31(lowA, lowB) == ((lowA & 0x80000000) != 0 ? lowB : 0))
            Swag.assert(signedBit(cast #bit(s64) a, cast #bit(s64) b) == ((a & 0x20000) != 0 ? cast #bit(s64) b : 0))
            Swag.assert(widenedBit(lowA, b) == ((lowA & 0x80000000) != 0 ? b : 0))
            Swag.assert(shared(a, b) == (((a & 0x20000) != 0 ? b : 0) ^ (a >> 17)))
        }
    }
}
