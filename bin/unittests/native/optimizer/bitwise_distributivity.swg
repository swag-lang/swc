#global private

#[Swag.NoInline]
func sharedAnd32(a, b, c: u32)->u32 => (a & b) | (a & c)

#[Swag.NoInline]
func sharedOr32(a, b, c: u32)->u32 => (a | b) & (a | c)

#[Swag.NoInline]
func sharedAnd64(a, b, c: u64)->u64 => (a & b) | (a & c)

#[Swag.NoInline]
func sharedOr64(a, b, c: u64)->u64 => (a | b) & (a | c)

#[Swag.NoInline]
func reusedAnd(a, b, c: u64)->u64
{
    let first = a & b
    return (first | (a & c)) ^ first
}

#[Swag.NoInline]
func changedOr(a, b, c: u64)->u64
{
    let first   = a | b
    let changed = a ^ 0xFF00FF00FF00FF00
    return first & (changed | c)
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA]
    for a in values
    {
        for b in values
        {
            for c in values
            {
                Swag.assert(sharedAnd64(a, b, c) == (a & (b | c)))
                Swag.assert(sharedOr64(a, b, c) == (a | (b & c)))
                let a32 = cast(u32) (a & 0xFFFFFFFF)
                let b32 = cast(u32) (b & 0xFFFFFFFF)
                let c32 = cast(u32) (c & 0xFFFFFFFF)
                Swag.assert(sharedAnd32(a32, b32, c32) == (a32 & (b32 | c32)))
                Swag.assert(sharedOr32(a32, b32, c32) == (a32 | (b32 & c32)))
                Swag.assert(reusedAnd(a, b, c) == (a & c & ~b))
                Swag.assert(changedOr(a, b, c) == ((a | b) & ((a ^ 0xFF00FF00FF00FF00) | c)))
            }
        }
    }
}
