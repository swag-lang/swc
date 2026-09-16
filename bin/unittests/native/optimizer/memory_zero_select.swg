#global private

#[Swag.NoInline]
func below(p: *u64, limit, value: u64)->u64 => p[] < limit ? value : 0
#[Swag.NoInline]
func equal(p: *u64, limit, value: u64)->u64 => p[] == limit ? value : 0
#[Swag.NoInline]
func constant(p: *u64, value: u64)->u64 => p[] == 17 ? value : 0
#[Swag.NoInline]
func above32(p: *u32, limit, value: u32)->u32 => p[] > limit ? value : 0
#[Swag.NoInline]
func live(p: *u64, limit, value: u64)->u64
{
    let selected = p[] < limit ? value : 0
    return selected ^ value ^ p[]
}
#[Swag.NoInline]
func bit(a, value: u64)->u64 => (a & 7) != 0 ? value : 0

#test
{
    let values = [0'u64, 1, 7, 17, 0xFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        var stored = a
        var narrow = cast(u32) (a & 0xFFFFFFFF)
        for b in values
        {
            let expected = a < b ? 91'u64 : 0
            Swag.assert(below(&stored, b, 91) == expected)
            Swag.assert(equal(&stored, b, 91) == (a == b ? 91 : 0))
            Swag.assert(live(&stored, b, 91) == (expected ^ 91 ^ a))
            let limit = cast(u32) (b & 0xFFFFFFFF)
            Swag.assert(above32(&narrow, limit, 91) == (narrow > limit ? 91 : 0))
        }
        Swag.assert(constant(&stored, 91) == (a == 17 ? 91 : 0))
        Swag.assert(bit(a, 91) == ((a & 7) != 0 ? 91 : 0))
    }
}
