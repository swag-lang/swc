using Swag, Core

// Ranks the subtable formats this module reads. The format rank dominates the
// platform score, so a rich map is never lost to a better-placed poor one.
// Format 13 folds whole planes onto a single glyph, which is only ever the right
// answer when nothing else is present.
// A format the module cannot read scores below zero and is skipped.
func scoreCMapFormat(format: u16)->s32
{
    switch format
    {
    case 12: return 5000
    case 8:  return 4600
    case 10: return 4500
    case 4:  return 4000
    case 6:  return 3000
    case 0:  return 2000
    case 13: return 1000
    }

    return -1
}

// Format 0: a flat 256-entry byte map, still used by small and very old faces.
func lookupCMap0(cmap: const [..] u8, charCode: u32)->u32
{
    if charCode > 0xFF do
        return 0
    return peekU8(cmap, 6 + cast(u64, charCode))
}

private const CMap4EndCodes = 14'u64

private struct CMap4Layout
{
    segmentCount: u64
    startCodes:   u64
    deltas:       u64
    ranges:       u64
}

#[Swag.Inline]
private func cmap4Layout(cmap: const [..] u8)->CMap4Layout
{
    let segmentCount = cast(u64, peekU16(cmap, 6) / 2)
    let segmentBytes = segmentCount * 2
    let startCodes   = CMap4EndCodes + segmentBytes + 2
    let deltas       = startCodes + segmentBytes
    return {segmentCount, startCodes, deltas, deltas + segmentBytes}
}

#[Swag.Inline]
private func cmap4Glyph(cmap: const [..] u8, code, start: u32, delta: s16, rangePosition: u64, rangeOffset: u16)->u32
{
    if not rangeOffset do
        return cast(u32, (cast(s32, code) + delta) & 0xFFFF)

    let glyphPosition = rangePosition + rangeOffset + cast(u64, code - start) * 2
    if glyphPosition + 2 > cmap.count do
        return 0

    let glyph = peekU16(cmap, glyphPosition)
    return glyph ? cast(u32, (cast(s32, glyph) + delta) & 0xFFFF) : 0
}

func lookupCMap4(cmap: const [..] u8, charCode: u32)->u32
{
    if charCode > 0xFFFF do
        return 0

    let layout = cmap4Layout(cmap)

    // Search the first segment whose end code covers the character.
    var lo = 0'u64
    var hi = layout.segmentCount
    while lo < hi
    {
        let mid     = lo + (hi - lo) / 2
        let endCode = peekU16(cmap, CMap4EndCodes + mid * 2)
        if charCode > endCode do
            lo = mid + 1
        else do
            hi = mid
    }

    if lo >= layout.segmentCount do
        return 0

    let start = peekU16(cmap, layout.startCodes + lo * 2)
    if charCode < start do
        return 0

    let delta = peekS16(cmap, layout.deltas + lo * 2)
    let range = layout.ranges + lo * 2
    return cmap4Glyph(cmap, charCode, start, delta, range, peekU16(cmap, range))
}

// Format 6: one contiguous run of codes, which is how a face covering a single
// script block stays small.
func lookupCMap6(cmap: const [..] u8, charCode: u32)->u32
{
    let firstCode  = cast(u32, peekU16(cmap, 6))
    let entryCount = cast(u32, peekU16(cmap, 8))
    if charCode < firstCode or charCode - firstCode >= entryCount do
        return 0
    return peekU16(cmap, 10 + cast(u64, (charCode - firstCode)) * 2)
}

// Format 10: a trimmed array of glyph IDs indexed by Unicode scalar value.
func lookupCMap10(cmap: const [..] u8, charCode: u32)->u32
{
    let firstCode = peekU32(cmap, 12)
    if charCode < firstCode do
        return 0

    let index     = charCode - firstCode
    let charCount = peekU32(cmap, 16)
    if index >= charCount do
        return 0

    return peekU16(cmap, 20 + cast(u64, index) * 2)
}

// Format 8 mixes single UTF-16 units with packed surrogate pairs in its groups.
func lookupCMap8(cmap: const [..] u8, charCode: u32)->u32
{
    if charCode > 0x10FFFF or (charCode >= 0xD800 and charCode <= 0xDFFF) do
        return 0

    var mappedCode = charCode
    if charCode > 0xFFFF
    {
        let scalar = charCode - 0x10000
        let high   = 0xD800'u32 + (scalar >> 10)
        let low    = 0xDC00'u32 + (scalar & 0x3FF)
        let bit    = cast(u8, 0x80 >> (high & 7))
        if (peekU8(cmap, 12 + cast(u64, high >> 3)) & bit) == 0 do
            return 0
        mappedCode = (high << 16) | low
    }

    let numGroups = peekU32(cmap, 8204)
    var left      = 0'u32
    var right     = numGroups
    while left < right
    {
        let mid       = left + (right - left) / 2
        let base      = 8208'u64 + cast(u64, mid) * 12
        let startCode = peekU32(cmap, base)
        let endCode   = peekU32(cmap, base + 4)
        if mappedCode < startCode
        {
            right = mid
            continue
        }

        if mappedCode > endCode
        {
            left = mid + 1
            continue
        }

        return peekU32(cmap, base + 8) + (mappedCode - startCode)
    }

    return 0
}

func lookupCMap12(cmap: const [..] u8, charCode: u32)->u32
{
    let numGroups = peekU32(cmap, 12)
    var left      = 0'u32
    var right     = numGroups

    while left < right
    {
        let mid       = left + (right - left) / 2
        let base      = 16'u64 + cast(u64, mid) * 12
        let startCode = peekU32(cmap, base + 0)
        let endCode   = peekU32(cmap, base + 4)
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

        return peekU32(cmap, base + 8) + (charCode - startCode)
    }

    return 0
}

// Format 13: the same group array as format 12, except every code in a group maps
// to the one glyph the group names. This is what a last-resort face is made of.
func lookupCMap13(cmap: const [..] u8, charCode: u32)->u32
{
    let numGroups = peekU32(cmap, 12)
    var left      = 0'u32
    var right     = numGroups

    while left < right
    {
        let mid       = left + (right - left) / 2
        let base      = 16'u64 + cast(u64, mid) * 12
        let startCode = peekU32(cmap, base + 0)
        let endCode   = peekU32(cmap, base + 4)
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

        return peekU32(cmap, base + 8)
    }

    return 0
}

// Returns the offset of the format-14 selector record for 'selector', or zero when
// the face registers no sequence for it. Records are sorted by selector value.
func findVariationSelector(cmap: const [..] u8, selector: u32)->u64
{
    let recordCount = peekU32(cmap, 6)
    var left        = 0'u32
    var right       = recordCount

    while left < right
    {
        let mid   = left + (right - left) / 2
        let base  = 10'u64 + cast(u64, mid) * 11
        let value = peekU24(cmap, base)
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
func isDefaultVariation(cmap: const [..] u8, listOffset, charCode: u32)->bool
{
    let rangeCount = peekU32(cmap, cast(u64, listOffset))
    var left       = 0'u32
    var right      = rangeCount

    while left < right
    {
        let mid   = left + (right - left) / 2
        let base  = cast(u64, listOffset) + 4 + cast(u64, mid) * 4
        let start = peekU24(cmap, base)
        if charCode < start
        {
            right = mid
            continue
        }

        // The record stores how many code points follow the first one, so a lone
        // code point carries a count of zero.
        if charCode > start + peekU8(cmap, base + 3)
        {
            left = mid + 1
            continue
        }

        return true
    }

    return false
}

// Returns the glyph the non-default-UVS list assigns to 'charCode', or zero.
func lookupNonDefaultVariation(cmap: const [..] u8, listOffset, charCode: u32)->u32
{
    let mappingCount = peekU32(cmap, cast(u64, listOffset))
    var left         = 0'u32
    var right        = mappingCount

    while left < right
    {
        let mid   = left + (right - left) / 2
        let base  = cast(u64, listOffset) + 4 + cast(u64, mid) * 5
        let value = peekU24(cmap, base)
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

        return peekU16(cmap, base + 3)
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
    if not cmap do
        return 0

    let record = findVariationSelector(cmap, selector)
    if not record do
        return 0

    let nonDefaultOffset = peekU32(cmap, record + 7)
    if nonDefaultOffset do
        return lookupNonDefaultVariation(cmap, nonDefaultOffset, charCode)

    return 0
}

// Returns whether the face declares 'charCode' followed by 'selector' at all, in
// either the default or the non-default list.
func hasVariationSequence(faceData: *FaceImpl, charCode, selector: u32)->bool fail
{
    let cmap = faceData.variationCMap
    if not cmap do
        return false

    let record = findVariationSelector(cmap, selector)
    if not record do
        return false

    let defaultOffset = peekU32(cmap, record + 3)
    if defaultOffset and isDefaultVariation(cmap, defaultOffset, charCode) do
        return true

    let nonDefaultOffset = peekU32(cmap, record + 7)
    return nonDefaultOffset != 0 and lookupNonDefaultVariation(cmap, nonDefaultOffset, charCode) != 0
}

func lookupGlyphIndex(faceData: const *FaceImpl, charCode: u32)->u32 fail
{
    // A bare CFF or Type 1 program declares no character map; the one derived from its
    // built-in encoding answers in its place.
    if not faceData.hasCMap
    {
        let glyphIndex = faceData.syntheticCMap.getOrDefault(charCode, 0)
        return glyphIndex < faceData.face.glyphCount ? glyphIndex : 0
    }

    let cmap       = faceData.chosenCMap
    var glyphIndex = 0'u32
    switch faceData.cmapFormat
    {
    case 0:  glyphIndex = lookupCMap0(cmap, charCode)
    case 4:  glyphIndex = lookupCMap4(cmap, charCode)
    case 6:  glyphIndex = lookupCMap6(cmap, charCode)
    case 8:  glyphIndex = lookupCMap8(cmap, charCode)
    case 10: glyphIndex = lookupCMap10(cmap, charCode)
    case 12: glyphIndex = lookupCMap12(cmap, charCode)
    case 13: glyphIndex = lookupCMap13(cmap, charCode)
    default: try fault(0x96)
    }

    return glyphIndex < faceData.face.glyphCount ? glyphIndex : 0
}

// The group ends are ordered and were validated with this face's glyph count.
private func(sequential: bool) visitCMapGroups(cmap: const [..] u8, first: u32, visitor: func||(rune, u32)->bool)
{
    let numGroups = peekU32(cmap, 12)
    var lower     = 0'u32
    var upper     = numGroups
    while lower < upper
    {
        let middle = lower + (upper - lower) / 2
        let end    = peekU32(cmap, 20'u64 + cast(u64, middle) * 12)
        if end < first do
            lower = middle + 1
        else do
            upper = middle
    }

    for index in lower until numGroups
    {
        let record = 16'u64 + cast(u64, index) * 12
        let start  = peekU32(cmap, record)
        let end    = peekU32(cmap, record + 4)
        let glyph  = peekU32(cmap, record + 8)
        #static if not sequential
        {
            if not glyph do
                continue
        }

        for code in Math.max(first, start) to end
        {
            let character = cast(rune, code)
            if not Utf8.isValidRune(character) do
                continue
            let glyphIndex = sequential ? glyph + (code - start) : glyph
            if glyphIndex and not visitor(character, glyphIndex) do
                return
        }
    }
}

// Stable end codes let the visitor match the first segment that lookup would use.
private func visitCMap4(cmap: const [..] u8, first, glyphCount: u32, visitor: func||(rune, u32)->bool)->bool
{
    if first > 0xFFFF do
        return true

    let layout      = cmap4Layout(cmap)
    var previousEnd = 0'u16
    for index in layout.segmentCount
    {
        let end = peekU16(cmap, CMap4EndCodes + index * 2)
        if end < previousEnd do
            return false
        previousEnd = end
    }

    var nextCode = first
    for index in layout.segmentCount
    {
        let end = cast(u32, peekU16(cmap, CMap4EndCodes + index * 2))
        if end < nextCode do
            continue

        let start = cast(u32, peekU16(cmap, layout.startCodes + index * 2))
        let begin = Math.max(nextCode, start)
        nextCode = end + 1
        if begin > end do
            continue

        let delta       = peekS16(cmap, layout.deltas + index * 2)
        let range       = layout.ranges + index * 2
        let rangeOffset = peekU16(cmap, range)
        for code in begin to end
        {
            let character = cast(rune, code)
            if not Utf8.isValidRune(character) do
                continue
            let glyph = cmap4Glyph(cmap, code, start, delta, range, rangeOffset)
            if glyph and glyph < glyphCount and not visitor(character, glyph) do
                return true
        }
    }

    return true
}

func visitMappedCharacters(faceData: const *FaceImpl, first: u32, visitor: func||(rune, u32)->bool)
{
    const ScalarLimit = 0x110000'u64
    if first >= ScalarLimit do
        return

    if not faceData.hasCMap
    {
        var codes: Array'u32
        for code, glyph in faceData.syntheticCMap
        {
            if code >= first and
               code < ScalarLimit and
               glyph and
               glyph < faceData.face.glyphCount and
               Utf8.isValidRune(cast(rune, code)) do
                codes.add(code)
        }

        codes.sort()
        for code in codes
        {
            if not visitor(cast(rune, code), faceData.syntheticCMap.getOrDefault(code, 0)) do
                return
        }

        return
    }

    let cmap  = faceData.chosenCMap
    var start = cast(u64, first)
    var limit = ScalarLimit
    switch faceData.cmapFormat
    {
    case 0:
        limit = 0x100

    case 4:

        // Preserve lookup behavior for older fonts with an unordered segment array.
        if visitCMap4(cmap, first, faceData.face.glyphCount, visitor) do
            return
        limit = 0x10000

    case 6:
        let mapStart = cast(u64, peekU16(cmap, 6))
        start = Math.max(start, mapStart)
        limit = mapStart + peekU16(cmap, 8)

    case 10:
        let mapStart = cast(u64, peekU32(cmap, 12))
        start = Math.max(start, mapStart)
        limit = Math.min(ScalarLimit, mapStart + peekU32(cmap, 16))

    case 12:
        visitCMapGroups'true(cmap, first, visitor)
        return

    case 13:
        visitCMapGroups'false(cmap, first, visitor)
        return
    }

    if start >= limit do
        return

    for code in start until limit
    {
        let character = cast(rune, code)
        if not Utf8.isValidRune(character) do
            continue
        let glyph = catch lookupGlyphIndex(faceData, cast(u32, code)) orelse 0
        if glyph and not visitor(character, glyph) do
            return
    }
}
