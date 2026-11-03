#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func plus(a: u32)->u64
{
    let value: u32 = a + 1
    return value
}
#[Swag.NoInline]
func minus(a: u32)->u64
{
    let value: u32 = a - 1
    return value
}
#[Swag.NoInline]
func signedPlus(a: s32)->s64
{
    let value: s32 = a + 1
    return value
}
#[Swag.NoInline]
func factor(a, b: u32)->u32 => a * b + a
#[Swag.NoInline]
func subtract(a, b: u32)->u32 => a * b - a
#[Swag.NoInline]
func memory(p: *u32, a: u32)->u32 => p[] * a + p[]
#[Swag.NoInline]
func retainHigh(a: u64, b: u32)->u64
{
    let low         = cast(u32, (a & 0xFFFFFFFF))
    let result: u32 = low * b + low
    return cast(u64, result) ^ a
}
#[Swag.NoInline]
func loadAfterPlus(p: [*]u64, a: u32)->u64
{
    let index: u32 = a + 1
    return p[index]
}
#[Swag.NoInline]
func loadAfterMinus(p: [*]u64, a: u32)->u64
{
    let index: u32 = a - 1
    return p[index]
}
#[Swag.NoInline]
func indexedWrap(a: u32)->u64
{
    let index: u32 = a * 4 + 7
    return index
}

#test
{
    let values = [0'u32, 1, 7, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFE, 0xFFFFFFFF]
    for a in values
    {
        let added:   u32 = a + 1
        let removed: u32 = a - 1
        Swag.require(plus(a) == cast(u64, added))
        Swag.require(minus(a) == cast(u64, removed))
        let scaled: u32 = a * 4 + 7
        Swag.require(indexedWrap(a) == cast(u64, scaled))
        for b in values
        {
            let product: u32 = a * b
            Swag.require(factor(a, b) == product + a)
            Swag.require(subtract(a, b) == product - a)
            var cell = a
            Swag.require(memory(&cell, b) == product + a)
            let wide     = cast(u64, a) | 0xFEDCBA9800000000
            let sum: u32 = product + a
            Swag.require(retainHigh(wide, b) == (cast(u64, sum) ^ wide))
        }
    }
    Swag.require(signedPlus(0x7FFFFFFF) == -2147483648's64)
    Swag.require(signedPlus(-1) == 0)
    Swag.require(signedPlus(-2147483648) == -2147483647's64)
    var cells = [17'u64, 29, 41]
    Swag.require(loadAfterPlus(&cells[0], 0xFFFFFFFF) == 17)
    Swag.require(loadAfterPlus(&cells[0], 1) == 41)
    Swag.require(loadAfterMinus(&cells[0], 1) == 17)
}
