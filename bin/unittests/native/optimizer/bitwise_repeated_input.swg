#global private

#[Swag.NoInline]
func absorbOr32(a, b: u32)->u32 => a | (a & b)

#[Swag.NoInline]
func absorbAnd32(a, b: u32)->u32 => (a | b) & a

#[Swag.NoInline]
func cancelLeft32(a, b: u32)->u32 => (b ^ a) ^ a

#[Swag.NoInline]
func cancelRight32(a, b: u32)->u32 => a ^ (a ^ b)

#[Swag.NoInline]
func absorbXorOr32(a, b: u32)->u32 => a | (a ^ b)

#[Swag.NoInline]
func absorbOr64(a, b: u64)->u64 => a | (a & b)

#[Swag.NoInline]
func absorbAnd64(a, b: u64)->u64 => (a | b) & a

#[Swag.NoInline]
func cancelLeft64(a, b: u64)->u64 => (b ^ a) ^ a

#[Swag.NoInline]
func cancelRight64(a, b: u64)->u64 => a ^ (a ^ b)

#[Swag.NoInline]
func absorbXorOr64(a, b: u64)->u64 => (a ^ b) | b

#[Swag.NoInline]
func reusedXor(a, b: u64)->u64
{
    let first = a ^ b
    return (first ^ a) | first
}

#[Swag.NoInline]
func changedInput(a, b: u64)->u64
{
    let first = a & b
    let changed = a ^ 0xFF00FF00FF00FF00
    return first | changed
}

#test
{
    let values = [0'u64, 1, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF, 0x5555555555555555, 0xAAAAAAAAAAAAAAAA]
    for a in values
    {
        for b in values
        {
            let a32 = cast(u32) (a & 0xFFFFFFFF)
            let b32 = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(absorbOr32(a32, b32) == a32)
            Swag.assert(absorbAnd32(a32, b32) == a32)
            Swag.assert(cancelLeft32(a32, b32) == b32)
            Swag.assert(cancelRight32(a32, b32) == b32)
            Swag.assert(absorbXorOr32(a32, b32) == (a32 | b32))
            Swag.assert(absorbOr64(a, b) == a)
            Swag.assert(absorbAnd64(a, b) == a)
            Swag.assert(cancelLeft64(a, b) == b)
            Swag.assert(cancelRight64(a, b) == b)
            Swag.assert(absorbXorOr64(a, b) == (a | b))
            Swag.assert(reusedXor(a, b) == (a | b))
            Swag.assert(changedInput(a, b) == ((a & b) | (a ^ 0xFF00FF00FF00FF00)))
        }
    }
}
