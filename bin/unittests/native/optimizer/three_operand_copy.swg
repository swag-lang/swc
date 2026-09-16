#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func left(a, b: u32)->u32 => a << (b & 31)
#[Swag.NoInline]
func right(a, b: u32)->u32 => a >> (b & 31)
#[Swag.NoInline]
func signedRight(a: s32, b: u32)->s32 => a >> (b & 31)
#[Swag.NoInline]
func sameInput(a: u32)->u32 => a << (a & 31)
#[Swag.NoInline]
func shared(a, b: u32)->u32 => (a << (b & 31)) ^ a ^ b
#[Swag.NoInline]
func changedSource(a, b: u32)->u32
{
    var current = a
    let old = current
    current += b
    return (old << (b & 31)) ^ current
}
#[Swag.NoInline]
func maskWithLiveSource(a: u64, b, c: u64)->u64 => ((a & 7) == 0 ? b : c) ^ a

#test
{
    let values = [0'u32, 1, 7, 31, 32, 63, 0x80000000, 0x87654321, 0xFFFFFFFF]
    for a in values
    {
        Swag.assert(sameInput(a) == a << (a & 31))
        for b in values
        {
            let shifted = a << (b & 31)
            Swag.assert(left(a, b) == shifted)
            Swag.assert(right(a, b) == a >> (b & 31))
            Swag.assert(signedRight(cast #bit(s32) a, b) == (cast #bit(s32) a) >> (b & 31))
            Swag.assert(shared(a, b) == (shifted ^ a ^ b))
            Swag.assert(changedSource(a, b) == (shifted ^ (a + b)))
            Swag.assert(maskWithLiveSource(a, b, 17) == (((a & 7) == 0 ? cast(u64) b : 17) ^ a))
        }
    }
}
