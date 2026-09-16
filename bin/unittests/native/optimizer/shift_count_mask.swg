#global private
#global #[Swag.Safety(.Overflow, false)]

// Counts at or above the width are left to the shift instruction, which
// masks them; the overflow safety would reject them first.

#[Swag.NoInline]
func left(a, b: u64)->u64 => a << (b & 63)
#[Swag.NoInline]
func right(a, b: u64)->u64 => a >> (b & 63)
#[Swag.NoInline]
func signedRight(a: s64, b: u64)->s64 => a >> (b & 63)
#[Swag.NoInline]
func left32(a, b: u32)->u32 => a << (b & 31)
#[Swag.NoInline]
func right32(a, b: u32)->u32 => a >> (b & 31)
#[Swag.NoInline]
func signedRight32(a: s32, b: u32)->s32 => a >> (b & 31)
#[Swag.NoInline]
func widerMask(a, b: u64)->u64 => a << (b & 127)
#[Swag.NoInline]
func smallerMask(a, b: u64)->u64 => a << (b & 31)
#[Swag.NoInline]
func shared(a, b: u64)->u64
{
    let count = b & 63
    return (a << count) ^ count
}
#[Swag.NoInline]
func oracleLeft(a, b: u64)->u64 => a << b
#[Swag.NoInline]
func oracleRight(a, b: u64)->u64 => a >> b
#[Swag.NoInline]
func oracleSigned(a: s64, b: u64)->s64 => a >> b
#[Swag.NoInline]
func oracleSigned32(a: s32, b: u32)->s32 => a >> b

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xABCDEF0123456789, 0xFFFFFFFFFFFFFFFF]
    let counts = [0'u64, 1, 7, 31, 32, 33, 63, 64, 65, 127, 128, 255, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in counts
        {
            let masked = b & 63
            Swag.assert(left(a, b) == oracleLeft(a, masked))
            Swag.assert(right(a, b) == oracleRight(a, masked))
            Swag.assert(signedRight(cast #bit (s64) a, b) == oracleSigned(cast #bit (s64) a, masked))
            Swag.assert(widerMask(a, b) == oracleLeft(a, masked))
            Swag.assert(smallerMask(a, b) == oracleLeft(a, b & 31))
            Swag.assert(shared(a, b) == (oracleLeft(a, masked) ^ masked))
            let lowA = cast(u32) (a & 0xFFFFFFFF)
            let lowB = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(left32(lowA, lowB) == cast(u32) (oracleLeft(lowA, b & 31) & 0xFFFFFFFF))
            Swag.assert(right32(lowA, lowB) == oracleRight(lowA, b & 31))
            Swag.assert(signedRight32(cast #bit (s32) lowA, lowB) == oracleSigned32(cast #bit (s32) lowA, lowB & 31))
        }
    }
}
