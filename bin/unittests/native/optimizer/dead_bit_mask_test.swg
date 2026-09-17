#global private

#[Swag.NoInline]
func selectBit(a, b, c: u64)->u64 => (a & 1) != 0 ? b : c
#[Swag.NoInline]
func selectLow(a, b, c: u32)->u32 => (a & 0x65) == 0 ? b : c
#[Swag.NoInline]
func selectHigh(a, b, c: u64)->u64 => (a & 0x80) != 0 ? b : c
#[Swag.NoInline]
func positive(a, b, c: s64)->s64 => (a & 0x7F) > 0 ? b : c
#[Swag.NoInline]
func signBoundary(a, b, c: s64)->s64 => (a & 0x80) > 0 ? b : c
#[Swag.NoInline]
func shared(a: u64)->u64
{
    let masked = a & 0x65
    if masked != 0 do return masked ^ a
    return a
}
#[Swag.NoInline]
func extendedRegisters(a, b, c, d: u64)->u64 => (d & 0x43) != 0 ? a ^ c : b ^ c
#[Swag.NoInline]
func highMask(a, b, c: u64)->u64 => (a & 0x10000000001) != 0 ? b : c

#test
{
    let values = [0'u64, 1, 2, 4, 0x40, 0x7F, 0x80, 0xFF, 0x100, 0x10000000000, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        let low    = cast(u32) (a & 0xFFFFFFFF)
        let masked = a & 0x65
        Swag.assert(selectBit(a, 17, 29) == ((a & 1) != 0 ? 17 : 29))
        Swag.assert(selectLow(low, 17, 29) == ((low & 0x65) == 0 ? 17 : 29))
        Swag.assert(selectHigh(a, 17, 29) == ((a & 0x80) != 0 ? 17 : 29))
        Swag.assert(positive(cast(s64) (a & 0x7FFFFFFFFFFFFFFF), 17, 29) == ((a & 0x7F) != 0 ? 17 : 29))
        Swag.assert(signBoundary(cast(s64) (a & 0x7FFFFFFFFFFFFFFF), 17, 29) == ((a & 0x80) != 0 ? 17 : 29))
        Swag.assert(shared(a) == (masked != 0 ? masked ^ a : a))
        Swag.assert(extendedRegisters(17, 29, 91, a) == (((a & 0x43) != 0 ? 17'u64 : 29) ^ 91))
        Swag.assert(highMask(a, 17, 29) == ((a & 0x10000000001) != 0 ? 17 : 29))
    }
    Swag.assert(positive(-1, 17, 29) == 17)
    Swag.assert(signBoundary(-1, 17, 29) == 17)
}
