#global private

#[Swag.NoInline]
func leftOr(a, b: u64)->u64 => (a << 3) | (b << 3)
#[Swag.NoInline]
func leftAnd(a, b: u64)->u64 => (a << 3) & (b << 3)
#[Swag.NoInline]
func leftXor(a, b: u64)->u64 => (a << 3) ^ (b << 3)
#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func leftSubtract(a, b: u64)->u64 => (a << 3) - (b << 3)
#[Swag.NoInline]
func rightOr(a, b: u64)->u64 => (a >> 5) | (b >> 5)
#[Swag.NoInline]
func rightAnd(a, b: u64)->u64 => (a >> 5) & (b >> 5)
#[Swag.NoInline]
func rightXor(a, b: u64)->u64 => (a >> 5) ^ (b >> 5)
#[Swag.NoInline]
func signedRight(a, b: s64)->s64 => (a >> 5) ^ (b >> 5)
#[Swag.NoInline]
func narrow(a, b: u32)->u32 => (a << 3) | (b << 3)
#[Swag.NoInline]
func differentCounts(a, b: u64)->u64 => (a << 3) | (b << 4)
#[Swag.NoInline]
func shared(a, b: u64)->u64
{
    let shifted = a << 3
    return (shifted | (b << 3)) ^ shifted
}

#[Swag.Safety(.Overflow, false)]
#test
{
    let values = [0'u64, 1, 7, 31, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        for b in values
        {
            Swag.assert(leftOr(a, b) == (a | b) << 3)
            Swag.assert(leftAnd(a, b) == (a & b) << 3)
            Swag.assert(leftXor(a, b) == (a ^ b) << 3)
            Swag.assert(leftSubtract(a, b) == (a - b) << 3)
            Swag.assert(rightOr(a, b) == (a | b) >> 5)
            Swag.assert(rightAnd(a, b) == (a & b) >> 5)
            Swag.assert(rightXor(a, b) == (a ^ b) >> 5)
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(narrow(a32, b32) == (a32 | b32) << 3)
            Swag.assert(differentCounts(a, b) == ((a << 3) | (b << 4)))
            Swag.assert(shared(a, b) == ((b & ~a) << 3))
        }
    }
    Swag.assert(signedRight(-1, 31) == -1)
    Swag.assert(signedRight(-32, -64) == 1)
    Swag.assert(signedRight(64, -32) == -3)
}
