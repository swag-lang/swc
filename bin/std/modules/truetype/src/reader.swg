using Swag, Core

func assertRange(buffer: const [..] u8, offset, length: u64) fail
{
    if offset > buffer.count or length > buffer.count - offset do
        try fault(0x03)
}

func getSlice(buffer: const [..] u8, offset, length: u64)->const [..] u8 fail
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
func peekU8(buffer: const [..] u8, offset: u64)->u8
{
    if offset >= buffer.count do
        return 0
    let buf = buffer
    return buf[offset]
}

func peekU16(buffer: const [..] u8, offset: u64)->u16
{
    if offset > buffer.count do
        return 0
    if buffer.count - offset < 2 do
        return 0
    let buf = buffer
    return cast(u16, buf[offset]) << 8 | buf[offset + 1]
}

func peekS16(buffer: const [..] u8, offset: u64)->s16
{
    let value = peekU16(buffer, offset)
    if value <= 0x7FFF do
        return cast(s16, value)
    return cast(s16, (cast(s32, value) - 0x1_0000))
}

func peekU24(buffer: const [..] u8, offset: u64)->u32
{
    if offset > buffer.count do
        return 0
    if buffer.count - offset < 3 do
        return 0
    let buf = buffer
    return cast(u32, buf[offset]) << 16 | cast(u32, buf[offset + 1]) << 8 | buf[offset + 2]
}

func peekU32(buffer: const [..] u8, offset: u64)->u32
{
    if offset > buffer.count do
        return 0
    if buffer.count - offset < 4 do
        return 0
    let buf = buffer
    return cast(u32, buf[offset]) << 24 |
           cast(u32, buf[offset + 1]) << 16 |
           cast(u32, buf[offset + 2]) << 8 |
           buf[offset + 3]
}

func peekF2Dot14(buffer: const [..] u8, offset: u64)->f64 => peekS16(buffer, offset) / 16384.0

func readU8(buffer: const [..] u8, offset: u64)->u8 fail
{
    try assertRange(buffer, offset, 1)
    let buf = buffer
    return buf[offset]
}

func readU16(buffer: const [..] u8, offset: u64)->u16 fail
{
    try assertRange(buffer, offset, 2)
    let buf = buffer
    return cast(u16, buf[offset]) << 8 | buf[offset + 1]
}

func readS16(buffer: const [..] u8, offset: u64)->s16 fail
{
    let value = try readU16(buffer, offset)
    if value <= 0x7FFF do
        return cast(s16, value)
    return cast(s16, (cast(s32, value) - 0x1_0000))
}

// Reads the 24-bit big-endian form the 'cmap' format-14 subtable stores code points in.
func readU24(buffer: const [..] u8, offset: u64)->u32 fail
{
    try assertRange(buffer, offset, 3)
    let buf = buffer
    return cast(u32, buf[offset]) << 16 | cast(u32, buf[offset + 1]) << 8 | buf[offset + 2]
}

func readU32(buffer: const [..] u8, offset: u64)->u32 fail
{
    try assertRange(buffer, offset, 4)
    let buf = buffer
    return cast(u32, buf[offset]) << 24 |
           cast(u32, buf[offset + 1]) << 16 |
           cast(u32, buf[offset + 2]) << 8 |
           buf[offset + 3]
}

func readS32(buffer: const [..] u8, offset: u64)->s32 fail
{
    let value = try readU32(buffer, offset)
    if value <= 0x7FFF_FFFF do
        return cast(s32, value)
    return cast(s32, (cast(s64, value) - 0x1_0000_0000))
}

func readF2Dot14(buffer: const [..] u8, offset: u64)->f64 fail => try readS16(buffer, offset) / 16384.0

func roundDiv(value, divisor: s64)->s32
{
    if not divisor do
        return 0
    if value >= 0 do
        return cast(s32, ((value + divisor / 2) / divisor))
    return cast(s32, -(((-value) + divisor / 2) / divisor))
}

func scale26_6(value: s32, ppem, unitsPerEm: u32)->s32 fail
{
    if not unitsPerEm do
        try fault(0x17)

    let scaled  = cast(s64, value) * cast(s64, ppem) * 64
    let divisor = cast(s64, unitsPerEm)
    var rounded: s64
    if scaled >= 0 do
        rounded = (scaled + divisor / 2) / divisor
    else do
        rounded = -((-scaled + divisor / 2) / divisor)
    if rounded < Swag.S32.Min or rounded > Swag.S32.Max do
        try fault(0x17)
    return cast(s32, rounded)
}

#[Swag.Inline]
func readPackedOffset(entry: const [*] u8, width: u8)->u32
{
    switch width
    {
    case 1:  return entry[0]
    case 2:  return Math.make16(entry[0], entry[1])
    case 3:  return Math.make32(0, entry[0], entry[1], entry[2])
    default: return Math.make32(entry[0], entry[1], entry[2], entry[3])
    }
}

// Validates `count` adjacent pairs in a bounded sequence of `count + 1` offsets.
// The last offset bounds all earlier values once the sequence is known to be monotonic.
func(width: u8) validatePackedOffsets(offsets: const [*] u8, count: u32)->u32 fail
{
    var checked = 0'u32
    #static if Math.nativeToBigEndian(1'u16) != 1
    {
        #static if width == 2
        {
            const SwapWords = cast(Math.Simd.U8x16, [1'u8, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14])
            while count - checked >= 8
            {
                let entry     = offsets + cast(u64, checked) * 2
                let previous  = cast #bit(Math.Simd.U16x8, Math.Simd.permute(Math.Simd.load(entry), SwapWords))
                let following = cast #bit(Math.Simd.U16x8, Math.Simd.permute(Math.Simd.load(entry + 2), SwapWords))
                if Swag.vecMask(previous > following) do
                    try fault(0x08)
                checked += 8
            }
        }
        elif width == 3
        {
            const Previous  = cast(Math.Simd.U8x16, [2'u8, 1, 0, 128, 5, 4, 3, 128, 8, 7, 6, 128, 11, 10, 9, 128])
            const Following = cast(Math.Simd.U8x16, [5'u8, 4, 3, 128, 8, 7, 6, 128, 11, 10, 9, 128, 14, 13, 12, 128])

            // Five packed values occupy 15 bytes. Leave enough room for the full load.
            while count - checked >= 5
            {
                let packed    = Math.Simd.load(offsets + cast(u64, checked) * 3)
                let previous  = cast #bit(Math.Simd.U32x4, Math.Simd.shuffle(packed, Previous))
                let following = cast #bit(Math.Simd.U32x4, Math.Simd.shuffle(packed, Following))
                if Swag.vecMask(previous > following) do
                    try fault(0x08)
                checked += 4
            }
        }
        elif width == 4
        {
            const SwapOffsets = cast(Math.Simd.U8x16, [3'u8, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12])
            while count - checked >= 4
            {
                let entry     = offsets + cast(u64, checked) * 4
                let previous  = cast #bit(Math.Simd.U32x4, Math.Simd.permute(Math.Simd.load(entry), SwapOffsets))
                let following = cast #bit(Math.Simd.U32x4, Math.Simd.permute(Math.Simd.load(entry + 4), SwapOffsets))
                if Swag.vecMask(previous > following) do
                    try fault(0x08)
                checked += 4
            }
        }
    }

    var scalarEntry = offsets + cast(u64, checked) * width
    var lastOffset  = readPackedOffset(scalarEntry, width)
    scalarEntry += width
    for checked until count
    {
        let offset = readPackedOffset(scalarEntry, width)
        if offset < lastOffset do
            try fault(0x08)
        lastOffset  = offset
        scalarEntry += width
    }

    return lastOffset
}
