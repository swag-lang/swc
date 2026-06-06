using Swag, Core

func lookupCMap4(cmap: const [..] u8, charCode: u32)->u32 throw
{
    if charCode > 0xFFFF do
        return 0

    let segCount      = readU16(cmap, 6) / 2
    let endCodesOff   = 14'u64
    let startCodesOff = endCodesOff + cast(u64) segCount * 2 + 2
    let deltasOff     = startCodesOff + cast(u64) segCount * 2
    let rangesOff     = deltasOff + cast(u64) segCount * 2

    for segCount
    {
        let idx       = cast(u64) @index
        let endCode   = readU16(cmap, endCodesOff + idx * 2)
        if charCode > endCode do
            continue

        let startCode = readU16(cmap, startCodesOff + idx * 2)
        if charCode < startCode do
            return 0

        let delta     = readS16(cmap, deltasOff + idx * 2)
        let range     = readU16(cmap, rangesOff + idx * 2)
        if !range do
            return cast(u32) ((cast(s32) charCode + delta) & 0xFFFF)

        let rangePos  = rangesOff + idx * 2
        let glyphPos  = rangePos + range + cast(u64) (charCode - startCode) * 2
        if glyphPos + 2 > @countof(cmap) do
            return 0

        var glyph = readU16(cmap, glyphPos)
        if glyph do
            glyph = cast(u16) ((cast(s32) glyph + delta) & 0xFFFF)
        return glyph
    }

    return 0
}

func lookupCMap12(cmap: const [..] u8, charCode: u32)->u32 throw
{
    let numGroups = readU32(cmap, 12)
    var left      = 0'u32
    var right     = numGroups

    while left < right
    {
        let mid       = left + (right - left) / 2
        let base      = 16'u64 + cast(u64) mid * 12
        let startCode = readU32(cmap, base + 0)
        let endCode   = readU32(cmap, base + 4)
        if charCode < startCode
        {
            right = mid
            continue
        }

        if charCode > endCode
        {
            left = mid + 1
            continue
        }

        return readU32(cmap, base + 8) + (charCode - startCode)
    }

    return 0
}

func lookupGlyphIndex(faceData: *FaceImpl, charCode: u32)->u32 throw
{
    if faceData.cmapFormat == 4 do
        return lookupCMap4(faceData.chosenCMap, charCode)
    if faceData.cmapFormat == 12 do
        return lookupCMap12(faceData.chosenCMap, charCode)
    fail(0x96)
    return 0
}
