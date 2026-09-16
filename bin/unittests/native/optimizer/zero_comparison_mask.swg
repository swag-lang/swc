#global private

#[Swag.NoInline]
func zero(a: u64)->u64 => a == 0 ? 0xFFFFFFFFFFFFFFFF : 0
#[Swag.NoInline]
func nonzero(a: u64)->u64 => a != 0 ? 0xFFFFFFFFFFFFFFFF : 0
#[Swag.NoInline]
func zero32(a: u32)->u32 => a == 0 ? 0xFFFFFFFF : 0
#[Swag.NoInline]
func nonzero32(a: u32)->u32 => a != 0 ? 0xFFFFFFFF : 0
#[Swag.NoInline]
func shared(a: u64)->u64 => (a != 0 ? 0xFFFFFFFFFFFFFFFF : 0) ^ a
#[Swag.NoInline]
func equalShared(a: u64)->u64 => (a == 0 ? 0xFFFFFFFFFFFFFFFF : 0) ^ a
#[Swag.NoInline]
func isZero(a: u64)->bool => a == 0

#test
{
    let values = [0'u64, 1, 127, 128, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        var mask = 0'u64
        if isZero(a)
        {
            mask = 0xFFFFFFFFFFFFFFFF
            Swag.assert(zero(a) == 0xFFFFFFFFFFFFFFFF)
            Swag.assert(nonzero(a) == 0)
        }
        else
        {
            Swag.assert(zero(a) == 0)
            Swag.assert(nonzero(a) == 0xFFFFFFFFFFFFFFFF)
        }
        Swag.assert(shared(a) == (~mask ^ a))
        Swag.assert(equalShared(a) == (mask ^ a))
        let narrow = cast(u32) (a & 0xFFFFFFFF)
        if isZero(narrow)
        {
            Swag.assert(zero32(narrow) == 0xFFFFFFFF)
            Swag.assert(nonzero32(narrow) == 0)
        }
        else
        {
            Swag.assert(zero32(narrow) == 0)
            Swag.assert(nonzero32(narrow) == 0xFFFFFFFF)
        }
    }
}
