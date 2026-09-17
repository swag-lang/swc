#global private

#[Swag.NoInline]
func wideSelection(a, b: u64)->u64
{
    let first  = a < b ? 0x100000000 : 0
    let second = a < b ? 0 : 0x8000000000000000
    #assert(#sizeof(first) == 8)
    #assert(#sizeof(second) == 8)
    return first | second
}

#[Swag.NoInline]
func signedSelection(flag: bool)->s64
{
    let value = flag ? -0x100000000 : 7
    #assert(#sizeof(value) == 8)
    return value + 1
}

#[Swag.NoInline]
func ordinarySelection(flag: bool)->s32
{
    let value = flag ? 3 : 7
    #assert(#typeof(value) == s32)
    return value + 1
}

#[Swag.NoInline]
func contextSelection(flag: bool)->u8
{
    let value: u8 = flag ? 3 : 7
    #assert(#typeof(value) == u8)
    return value
}

#[Swag.NoInline]
func nestedSelection(first, second: bool)->u64
{
    let value = first ? (second ? 0x100000000 : 0x200000000) : 0
    return value | 1
}

#[Swag.NoInline]
func floatingSelection(flag: bool)->f64
{
    let value = flag ? 1.0e100 : 0.0
    #assert(#sizeof(value) == 8)
    return value * 2
}

#[Swag.NoInline]
func smallFloatingSelection(flag: bool) => flag ? -1.5 : 1.5

#test
{
    #assert(#typeof(smallFloatingSelection(true)) == f64)
    Swag.assert(smallFloatingSelection(true) == -1.5)
    Swag.assert(smallFloatingSelection(false) == 1.5)
    Swag.assert(floatingSelection(true) == 2.0e100)
    Swag.assert(floatingSelection(false) == 0)
    Swag.assert(wideSelection(0, 0) == 0x8000000000000000)
    Swag.assert(wideSelection(0, 1) == 0x100000000)
    Swag.assert(wideSelection(1, 0) == 0x8000000000000000)
    Swag.assert(signedSelection(true) == -0xFFFFFFFF)
    Swag.assert(signedSelection(false) == 8)
    Swag.assert(ordinarySelection(true) == 4)
    Swag.assert(ordinarySelection(false) == 8)
    Swag.assert(contextSelection(true) == 3)
    Swag.assert(contextSelection(false) == 7)
    Swag.assert(nestedSelection(true, true) == 0x100000001)
    Swag.assert(nestedSelection(true, false) == 0x200000001)
    Swag.assert(nestedSelection(false, true) == 1)
}
