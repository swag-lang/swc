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
        Swag.require(lowByte(&value) == (a & 0xFF))
        Swag.require(lowWord(&value) == (a & 0xFFFF))
        Swag.require(middleByte(&value) == ((a >> 16) & 0xFF))
        Swag.require(highWord(&value) == ((a >> 48) & 0xFFFF))
        Swag.require(highDword(&value) == (a >> 32))
        Swag.require(unalignedBits(&value) == ((a >> 17) & 0xFF))
        Swag.require(shared(&value) == (((a >> 16) & 0xFF) ^ a))
        Swag.require(sharedShift(&value) == (((a >> 16) & 0xFF) ^ (a >> 16)))
        Swag.require(compared(&value) == (((a >> 16) & 0xFF) == 0))
        Swag.require(stored(&value) == ((a >> 16) & 0xFF))
        Swag.require(value == 0)
    }
}
