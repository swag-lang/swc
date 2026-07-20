using Swag, Core

func assertRange(buffer: #null const [..] u8, offset, length: u64) throw
{
    if offset + length > @countof(buffer) do
        fail(0x03)
}

func getSlice(buffer: #null const [..] u8, offset, length: u64)->#null const [..] u8 throw
{
    assertRange(buffer, offset, length)
    return @mkslice(@dataof(buffer) + offset, length)
}

func readU8(buffer: #null const [..] u8, offset: u64)->u8 throw
{
    assertRange(buffer, offset, 1)
    return buffer[offset]
}

func readU16(buffer: #null const [..] u8, offset: u64)->u16 throw
{
    assertRange(buffer, offset, 2)
    return cast(u16) buffer[offset] << 8 | buffer[offset + 1]
}

func readS16(buffer: #null const [..] u8, offset: u64)->s16 throw
{
    let value = readU16(buffer, offset)
    if value <= 0x7FFF do
        return cast(s16) value
    return cast(s16) (cast(s32) value - 0x1_0000)
}

func readU32(buffer: #null const [..] u8, offset: u64)->u32 throw
{
    assertRange(buffer, offset, 4)
    return cast(u32) buffer[offset] << 24 | cast(u32) buffer[offset + 1] << 16 | cast(u32) buffer[offset + 2] << 8 | buffer[offset + 3]
}

func readS32(buffer: #null const [..] u8, offset: u64)->s32 throw
{
    let value = readU32(buffer, offset)
    if value <= 0x7FFF_FFFF do
        return cast(s32) value
    return cast(s32) (cast(s64) value - 0x1_0000_0000)
}

func readF2Dot14(buffer: #null const [..] u8, offset: u64)->f64 throw
{
    return readS16(buffer, offset) / 16384.0
}

func roundDiv(value, divisor: s64)->s32
{
    if !divisor do
        return 0
    if value >= 0 do
        return cast(s32) ((value + divisor / 2) / divisor)
    return cast(s32) -(((-value) + divisor / 2) / divisor)
}

func scaleFixed(ppem, unitsPerEm: u32)->s32
{
    return roundDiv(cast(s64) ppem * 64 * 65536, unitsPerEm)
}

func scale26_6(value: s32, ppem, unitsPerEm: u32)->s32
{
    return roundDiv(cast(s64) value * cast(s64) ppem * 64, unitsPerEm)
}
