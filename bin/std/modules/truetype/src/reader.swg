using Swag, Core

func assertRange(buffer: const [..] u8?, offset, length: u64) fail
{
    if offset + length > buffer.count do
        try fault(0x03)
}

func getSlice(buffer: const [..] u8?, offset, length: u64)->const [..] u8? fail
{
    try assertRange(buffer, offset, length)
    return Swag.makeSlice(buffer.buffer + offset, length)
}

// Reads that answer zero past the end of the table instead of raising.
//
// A table's extent is settled once, when the face is opened. Inside a glyph, a
// kerning pair or a charstring, every two bytes would otherwise carry a bounds
// check that raises and a check of that error at the caller, which is more code
// than the read itself - and there are thousands of them for one line of text.
// A font that points outside its own tables draws a wrong glyph here, which is
// what FreeType and stb_truetype also do, instead of failing mid-outline.
func peekU8(buffer: const [..] u8?, offset: u64)->u8
{
    if offset >= buffer.count do
        return 0
    let buf = buffer!
    return buf[offset]
}

func peekU16(buffer: const [..] u8?, offset: u64)->u16
{
    if offset + 2 > buffer.count do
        return 0
    let buf = buffer!
    return cast(u16) buf[offset] << 8 | buf[offset + 1]
}

func peekS16(buffer: const [..] u8?, offset: u64)->s16
{
    let value = peekU16(buffer, offset)
    if value <= 0x7FFF do
        return cast(s16) value
    return cast(s16) (cast(s32) value - 0x1_0000)
}

func peekU24(buffer: const [..] u8?, offset: u64)->u32
{
    if offset + 3 > buffer.count do
        return 0
    let buf = buffer!
    return cast(u32) buf[offset] << 16 | cast(u32) buf[offset + 1] << 8 | buf[offset + 2]
}

func peekU32(buffer: const [..] u8?, offset: u64)->u32
{
    if offset + 4 > buffer.count do
        return 0
    let buf = buffer!
    return cast(u32) buf[offset] << 24 | cast(u32) buf[offset + 1] << 16 | cast(u32) buf[offset + 2] << 8 | buf[offset + 3]
}

func peekF2Dot14(buffer: const [..] u8?, offset: u64)->f64
{
    return peekS16(buffer, offset) / 16384.0
}

func readU8(buffer: const [..] u8?, offset: u64)->u8 fail
{
    try assertRange(buffer, offset, 1)
    let buf = buffer!
    return buf[offset]
}

func readU16(buffer: const [..] u8?, offset: u64)->u16 fail
{
    try assertRange(buffer, offset, 2)
    let buf = buffer!
    return cast(u16) buf[offset] << 8 | buf[offset + 1]
}

func readS16(buffer: const [..] u8?, offset: u64)->s16 fail
{
    let value = try readU16(buffer, offset)
    if value <= 0x7FFF do
        return cast(s16) value
    return cast(s16) (cast(s32) value - 0x1_0000)
}

// Reads the 24-bit big-endian form the 'cmap' format-14 subtable stores code points in.
func readU24(buffer: const [..] u8?, offset: u64)->u32 fail
{
    try assertRange(buffer, offset, 3)
    let buf = buffer!
    return cast(u32) buf[offset] << 16 | cast(u32) buf[offset + 1] << 8 | buf[offset + 2]
}

func readU32(buffer: const [..] u8?, offset: u64)->u32 fail
{
    try assertRange(buffer, offset, 4)
    let buf = buffer!
    return cast(u32) buf[offset] << 24 | cast(u32) buf[offset + 1] << 16 | cast(u32) buf[offset + 2] << 8 | buf[offset + 3]
}

func readS32(buffer: const [..] u8, offset: u64)->s32 fail
{
    let value = try readU32(buffer, offset)
    if value <= 0x7FFF_FFFF do
        return cast(s32) value
    return cast(s32) (cast(s64) value - 0x1_0000_0000)
}

func readF2Dot14(buffer: const [..] u8?, offset: u64)->f64 fail
{
    return try readS16(buffer, offset) / 16384.0
}

func roundDiv(value, divisor: s64)->s32
{
    if not divisor do
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
