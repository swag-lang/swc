using Swag, Core

// Ranks the subtable formats this module reads. Consecutive ranks are a thousand
// apart and 'scoreNameRecord' never reaches seventy, so the format always outranks
// the platform score and a rich map is never lost to a better-placed poor one.
// Format 13 folds whole planes onto a single glyph, which is only ever the right
// answer when nothing else is present.
// A format the module cannot read scores below zero and is skipped.
func scoreCMapFormat(format: u16)->s32
{
    switch format
    {
    case 12: return 5000
    case 4:  return 4000
    case 6:  return 3000
    case 0:  return 2000
    case 13: return 1000
    }

    return -1
}

// Format 0: a flat 256-entry byte map, still used by small and very old faces.
func lookupCMap0(cmap: const [..] u8?, charCode: u32)->u32 fail
{
    if charCode > 0xFF do
        return 0
    return readU8(cmap, 6 + cast(u64) charCode)
}

func lookupCMap4(cmap: const [..] u8?, charCode: u32)->u32 fail
{
    if charCode > 0xFFFF do
        return 0

    let segCount      = readU16(cmap, 6) / 2
    let endCodesOff   = 14'u64
    let startCodesOff = endCodesOff + cast(u64) segCount * 2 + 2
    let deltasOff     = startCodesOff + cast(u64) segCount * 2
    let rangesOff     = deltasOff + cast(u64) segCount * 2

    // endCodes are sorted ascending: binary-search the first segment whose endCode
    // covers charCode, instead of scanning every segment (fonts have 100s of them).
    var lo = 0'u32
    var hi = cast(u32) segCount
    while lo < hi
    {
        let mid     = lo + (hi - lo) / 2
        let endCode = readU16(cmap, endCodesOff + cast(u64) mid * 2)
        if charCode > endCode do
            lo = mid + 1
        else do
            hi = mid
    }

    if lo >= cast(u32) segCount do
        return 0

    let idx       = cast(u64) lo
    let startCode = readU16(cmap, startCodesOff + idx * 2)
    if charCode < startCode do
        return 0

    let delta = readS16(cmap, deltasOff + idx * 2)
    let range = readU16(cmap, rangesOff + idx * 2)
    if !range do
        return cast(u32) ((cast(s32) charCode + delta) & 0xFFFF)

    let rangePos = rangesOff + idx * 2
    let glyphPos = rangePos + range + cast(u64) (charCode - startCode) * 2
    if glyphPos + 2 > cmap.count do
        return 0

    var glyph = readU16(cmap, glyphPos)
    if glyph do
        glyph = cast(u16) ((cast(s32) glyph + delta) & 0xFFFF)
    return glyph
}

// Format 6: one contiguous run of codes, which is how a face covering a single
// script block stays small.
func lookupCMap6(cmap: const [..] u8?, charCode: u32)->u32 fail
{
    let firstCode  = cast(u32) readU16(cmap, 6)
    let entryCount = cast(u32) readU16(cmap, 8)
    if charCode < firstCode or charCode - firstCode >= entryCount do
        return 0
    return readU16(cmap, 10 + cast(u64) (charCode - firstCode) * 2)
}

func lookupCMap12(cmap: const [..] u8?, charCode: u32)->u32 fail
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

// Format 13: the same group array as format 12, except every code in a group maps
// to the one glyph the group names. This is what a last-resort face is made of.
func lookupCMap13(cmap: const [..] u8?, charCode: u32)->u32 fail
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

        return readU32(cmap, base + 8)
    }

    return 0
}

// Returns the offset of the format-14 selector record for 'selector', or zero when
// the face registers no sequence for it. Records are sorted by selector value.
func findVariationSelector(cmap: const [..] u8?, selector: u32)->u64 fail
{
    let recordCount = readU32(cmap, 6)
    var left        = 0'u32
    var right       = recordCount

    while left < right
    {
        let mid   = left + (right - left) / 2
        let base  = 10'u64 + cast(u64) mid * 11
        let value = readU24(cmap, base)
        if selector < value
        {
            right = mid
            continue
        }

        if selector > value
        {
            left = mid + 1
            continue
        }

        return base
    }

    return 0
}

// Returns whether the default-UVS range list registers 'charCode'. Such a sequence
// resolves through the ordinary map, so the selector only confirms the default glyph.
func isDefaultVariation(cmap: const [..] u8?, listOffset, charCode: u32)->bool fail
{
    let rangeCount = readU32(cmap, cast(u64) listOffset)
    var left       = 0'u32
    var right      = rangeCount

    while left < right
    {
        let mid   = left + (right - left) / 2
        let base  = cast(u64) listOffset + 4 + cast(u64) mid * 4
        let start = readU24(cmap, base)
        if charCode < start
        {
            right = mid
            continue
        }

        // The record stores how many code points follow the first one, so a lone
        // code point carries a count of zero.
        if charCode > start + readU8(cmap, base + 3)
        {
            left = mid + 1
            continue
        }

        return true
    }

    return false
}

// Returns the glyph the non-default-UVS list assigns to 'charCode', or zero.
func lookupNonDefaultVariation(cmap: const [..] u8?, listOffset, charCode: u32)->u32 fail
{
    let mappingCount = readU32(cmap, cast(u64) listOffset)
    var left         = 0'u32
    var right        = mappingCount

    while left < right
    {
        let mid   = left + (right - left) / 2
        let base  = cast(u64) listOffset + 4 + cast(u64) mid * 5
        let value = readU24(cmap, base)
        if charCode < value
        {
            right = mid
            continue
        }

        if charCode > value
        {
            left = mid + 1
            continue
        }

        return readU16(cmap, base + 3)
    }

    return 0
}

// Resolves 'charCode' followed by 'selector' through the format-14 subtable.
//
// Returns zero when the face registers no glyph for the pair, which is also the
// answer for a sequence the face declares to use its default glyph: the caller
// then resolves 'charCode' alone through the selected map and reaches the same
// glyph either way.
func lookupVariationGlyph(faceData: *FaceImpl, charCode, selector: u32)->u32 fail
{
    let cmap = faceData.variationCMap
    if !cmap do
        return 0

    let record = findVariationSelector(cmap, selector)
    if !record do
        return 0

    let nonDefaultOffset = readU32(cmap, record + 7)
    if nonDefaultOffset do
        return lookupNonDefaultVariation(cmap, nonDefaultOffset, charCode)

    return 0
}

// Returns whether the face declares 'charCode' followed by 'selector' at all, in
// either the default or the non-default list.
func hasVariationSequence(faceData: *FaceImpl, charCode, selector: u32)->bool fail
{
    let cmap = faceData.variationCMap
    if !cmap do
        return false

    let record = findVariationSelector(cmap, selector)
    if !record do
        return false

    let defaultOffset = readU32(cmap, record + 3)
    if defaultOffset and isDefaultVariation(cmap, defaultOffset, charCode) do
        return true

    let nonDefaultOffset = readU32(cmap, record + 7)
    return nonDefaultOffset != 0 and lookupNonDefaultVariation(cmap, nonDefaultOffset, charCode) != 0
}

func lookupGlyphIndex(faceData: *FaceImpl, charCode: u32)->u32 fail
{
    // A bare CFF or Type 1 program declares no character map; the one derived from its
    // built-in encoding answers in its place.
    if !faceData.hasCMap do
        return faceData.syntheticCMap.getOrDefault(charCode, 0)

    let cmap = faceData.chosenCMap
    switch faceData.cmapFormat
    {
    case 0:  return lookupCMap0(cmap, charCode)
    case 4:  return lookupCMap4(cmap, charCode)
    case 6:  return lookupCMap6(cmap, charCode)
    case 12: return lookupCMap12(cmap, charCode)
    case 13: return lookupCMap13(cmap, charCode)
    }

    fault(0x96)
    return 0
}
