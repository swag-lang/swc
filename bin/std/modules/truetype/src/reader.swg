using Swag, Core

func assertRange(buffer: #null const [..] u8, offset, length: u64) fail
{
    if offset + length > @countof(buffer) do
        fault(0x03)
}

func getSlice(buffer: #null const [..] u8, offset, length: u64)->#null const [..] u8 fail
{
    assertRange(buffer, offset, length)
    return @mkslice(@dataof(buffer) + offset, length)
}

func readU8(buffer: #null const [..] u8, offset: u64)->u8 fail
{
    assertRange(buffer, offset, 1)
    let buf = buffer!
    return buf[offset]
}

func readU16(buffer: #null const [..] u8, offset: u64)->u16 fail
{
    assertRange(buffer, offset, 2)
    let buf = buffer!
    return cast(u16) buf[offset] << 8 | buf[offset + 1]
}

func readS16(buffer: #null const [..] u8, offset: u64)->s16 fail
{
    let value = readU16(buffer, offset)
    if value <= 0x7FFF do
        return cast(s16) value
    return cast(s16) (cast(s32) value - 0x1_0000)
}

// Reads the 24-bit big-endian form the 'cmap' format-14 subtable stores code points in.
func readU24(buffer: #null const [..] u8, offset: u64)->u32 fail
{
    assertRange(buffer, offset, 3)
    let buf = buffer!
    return cast(u32) buf[offset] << 16 | cast(u32) buf[offset + 1] << 8 | buf[offset + 2]
}

func readU32(buffer: #null const [..] u8, offset: u64)->u32 fail
{
    assertRange(buffer, offset, 4)
    let buf = buffer!
    return cast(u32) buf[offset] << 24 | cast(u32) buf[offset + 1] << 16 | cast(u32) buf[offset + 2] << 8 | buf[offset + 3]
}

func readS32(buffer: const [..] u8, offset: u64)->s32 fail
{
    let value = readU32(buffer, offset)
    if value <= 0x7FFF_FFFF do
        return cast(s32) value
    return cast(s32) (cast(s64) value - 0x1_0000_0000)
}

func readF2Dot14(buffer: #null const [..] u8, offset: u64)->f64 fail
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
