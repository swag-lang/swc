#global private

// A select between two constants one apart on an unsigned compare adds or
// subtracts the carry. Both directions, both senses of the compare, bytes,
// dwords and qwords must agree with the same selects left unoptimized.

#[Swag.Optimize(true), Swag.NoInline]
func utf8Len(c: u8)->u32
{
    if c < 0x80 do return 1
    if c < 0xE0 do return 2
    if c < 0xF0 do return 3
    return 4
}
#[Swag.Optimize(true), Swag.NoInline]
func belowMinusOne(x, y: u32)->u32 => x < y ? 9 : 10
#[Swag.Optimize(true), Swag.NoInline]
func belowPlusOne(x, y: u32)->u32 => x < y ? 11 : 10
#[Swag.Optimize(true), Swag.NoInline]
func notBelowMinusOne(x, y: u64)->u64 => x >= y ? 0xFFFFFFFF : 0x100000000
#[Swag.Optimize(true), Swag.NoInline]
func notBelowPlusOne(x, y: u64)->u64 => x >= y ? 0 : 0xFFFFFFFFFFFFFFFF
#[Swag.Optimize(true), Swag.NoInline]
func wrapAround(x, y: u32)->u32 => x < y ? 0xFFFFFFFF : 0
#[Swag.Optimize(true), Swag.NoInline]
func negativeBelow(x, y: u32)->s32 => x < y ? -9 : -10
#[Swag.Optimize(true), Swag.NoInline]
func negativeNotBelow(x, y: u32)->s32 => x < y ? -10 : -9
#[Swag.Optimize(true), Swag.NoInline]
func wideNegativeBelow(x, y: u64)->s64 => x < y ? -1000 : -1001

#[Swag.Optimize(false), Swag.NoInline]
func slowUtf8Len(c: u8)->u32
{
    if c < 0x80 do return 1
    if c < 0xE0 do return 2
    if c < 0xF0 do return 3
    return 4
}
#[Swag.Optimize(false), Swag.NoInline]
func slowBelow(x, y: u64)->bool => x < y

#test
{
    for i in 0 until 256
    {
        let c = cast(u8) i
        Swag.assert(utf8Len(c) == slowUtf8Len(c))
    }

    let values = [0'u64, 1, 2, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFE, 0xFFFFFFFF, 0x100000000, 0xFFFFFFFFFFFFFFFF]
    for x in values
    {
        for y in values
        {
            let x32     = cast #wrap (u32) x
            let y32     = cast #wrap (u32) y
            let below32 = slowBelow(cast(u64) x32, cast(u64) y32)
            Swag.assert(belowMinusOne(x32, y32) == (below32 ? 9 : 10))
            Swag.assert(belowPlusOne(x32, y32) == (below32 ? 11 : 10))
            Swag.assert(wrapAround(x32, y32) == (below32 ? 0xFFFFFFFF : 0))
            Swag.assert(negativeBelow(x32, y32) == (below32 ? -9 : -10))
            Swag.assert(negativeNotBelow(x32, y32) == (below32 ? -10 : -9))
            let below = slowBelow(x, y)
            Swag.assert(notBelowMinusOne(x, y) == (below ? 0x100000000 : 0xFFFFFFFF))
            Swag.assert(notBelowPlusOne(x, y) == (below ? 0xFFFFFFFFFFFFFFFF : 0))
            Swag.assert(wideNegativeBelow(x, y) == (below ? -1000 : -1001))
        }
    }
}
