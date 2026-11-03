#global private

#[Swag.NoInline]
func below128(a: u64)->u64 => a < 128 ? a : 0

#[Swag.NoInline]
func atLeast128(a: u64)->u64 => a < 128 ? 0 : a

#[Swag.NoInline]
func below32(a: u32)->u32 => a < 128 ? a : 0

#[Swag.NoInline]
func atLeast32(a, b: u32)->u32 => a < b ? 0 : a

#[Swag.NoInline]
func positive(a: s64)->s64 => a > 0 ? a : 0

#[Swag.NoInline]
func sharedInput(a, b: u64)->u64
{
    let selected = a < b ? a : 0
    return selected ^ a ^ b
}

#test
{
    let values = [0'u64, 1, 127, 128, 129, 0xFFFFFFFF, 0x100000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        var expected = 0'u64
        if a < 128 do expected = a
        Swag.require(below128(a) == expected)
        Swag.require(atLeast128(a) == (a ^ expected))
        let narrow = cast(u32, (a & 0xFFFFFFFF))
        Swag.require(below32(narrow) == (narrow < 128 ? narrow : 0))
        for b in values
        {
            let narrowB = cast(u32, (b & 0xFFFFFFFF))
            Swag.require(atLeast32(narrow, narrowB) == (narrow < narrowB ? 0 : narrow))
            var selected = 0'u64
            if a < b do selected = a
            Swag.require(sharedInput(a, b) == (selected ^ a ^ b))
        }
    }
    Swag.require(positive(-0x7FFFFFFFFFFFFFFF - 1) == 0)
    Swag.require(positive(-1) == 0)
    Swag.require(positive(0) == 0)
    Swag.require(positive(0x7FFFFFFFFFFFFFFF) == 0x7FFFFFFFFFFFFFFF)
}
