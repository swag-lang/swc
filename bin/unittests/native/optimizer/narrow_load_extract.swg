#global private

#[Swag.NoInline]
func lowByte(p: *u64)->u64 => p[] & 0xFF
#[Swag.NoInline]
func lowWord(p: *u64)->u64 => p[] & 0xFFFF
#[Swag.NoInline]
func middleByte(p: *u64)->u64 => (p[] >> 16) & 0xFF
#[Swag.NoInline]
func highWord(p: *u64)->u64 => (p[] >> 48) & 0xFFFF
#[Swag.NoInline]
func highDword(p: *u64)->u64 => (p[] >> 32) & 0xFFFFFFFF
#[Swag.NoInline]
func unalignedBits(p: *u64)->u64 => (p[] >> 17) & 0xFF
#[Swag.NoInline]
func shared(p: *u64)->u64
{
    let value = p[]
    return ((value >> 16) & 0xFF) ^ value
}
#[Swag.NoInline]
func sharedShift(p: *u64)->u64
{
    let value = p[] >> 16
    return (value & 0xFF) ^ value
}
#[Swag.NoInline]
func stored(p: *u64)->u64
{
    let value = p[]
    p[] = 0
    return (value >> 16) & 0xFF
}
#[Swag.NoInline]
func compared(p: *u64)->bool => ((p[] >> 16) & 0xFF) == 0

#test
{
    let values = [0'u64, 1, 0xFF, 0x10000, 0xFF0000, 0x8000000000000000, 0xABCDEF0123456789, 0xFFFFFFFFFFFFFFFF]
    for a in values
    {
        var value = a
        Swag.assert(lowByte(&value) == (a & 0xFF))
        Swag.assert(lowWord(&value) == (a & 0xFFFF))
        Swag.assert(middleByte(&value) == ((a >> 16) & 0xFF))
        Swag.assert(highWord(&value) == ((a >> 48) & 0xFFFF))
        Swag.assert(highDword(&value) == (a >> 32))
        Swag.assert(unalignedBits(&value) == ((a >> 17) & 0xFF))
        Swag.assert(shared(&value) == (((a >> 16) & 0xFF) ^ a))
        Swag.assert(sharedShift(&value) == (((a >> 16) & 0xFF) ^ (a >> 16)))
        Swag.assert(compared(&value) == (((a >> 16) & 0xFF) == 0))
        Swag.assert(stored(&value) == ((a >> 16) & 0xFF))
        Swag.assert(value == 0)
    }
}
