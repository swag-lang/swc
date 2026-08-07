using Swag, Core

// Lookup type of a pair-adjustment subtable, and of the extension wrapper that
// lets a lookup live beyond the 64K a 16-bit offset reaches.
const GPOS_LOOKUP_PAIR      = 2'u16
const GPOS_LOOKUP_EXTENSION = 9'u16

// Byte size of a value record, one two-byte field per set bit of its format.
func valueRecordSize(valueFormat: u16)->u64
{
    var size = 0'u64
    var bits = valueFormat
    while bits
    {
        size += 2
        bits &= cast(u16) (bits - 1)
    }

    return size
}

// Byte offset of the horizontal advance inside a value record, or -1 when the
// format declares none. Fields appear in value-format bit order, two bytes each,
// so only the two placement fields can precede the advance.
func xAdvanceOffset(valueFormat: u16)->s32
{
    if (valueFormat & 0x0004) == 0 do
        return -1

    var offset = 0
    if (valueFormat & 0x0001) != 0 do
        offset += 2
    if (valueFormat & 0x0002) != 0 do
        offset += 2
    return offset
}

// Returns the coverage index of 'glyph', or -1 when the table does not cover it.
// Both coverage formats are sorted, so both are binary-searched.
func coverageIndex(table: #null const [..] u8, offset: u64, glyph: u16)->s32 fail
{
    let format = readU16(table, offset + 0)
    let count  = readU16(table, offset + 2)

    var left  = 0'u32
    var right = cast(u32) count

    if format == 1
    {
        while left < right
        {
            let mid   = left + (right - left) / 2
            let value = readU16(table, offset + 4 + cast(u64) mid * 2)
            if glyph < value
            {
                right = mid
                continue
            }

            if glyph > value
            {
                left = mid + 1
                continue
            }

            return cast(s32) mid
        }

        return -1
    }

    if format != 2 do
        return -1

    // Ranges, each naming the coverage index its first glyph carries.
    while left < right
    {
        let mid        = left + (right - left) / 2
        let base       = offset + 4 + cast(u64) mid * 6
        let startGlyph = readU16(table, base + 0)
        let endGlyph   = readU16(table, base + 2)
        if glyph < startGlyph
        {
            right = mid
            continue
        }

        if glyph > endGlyph
        {
            left = mid + 1
            continue
        }

        return cast(s32) readU16(table, base + 4) + cast(s32) (glyph - startGlyph)
    }

    return -1
}

// Returns the class of 'glyph' in a class-definition table. Class zero is the
// implicit class of every glyph the table does not list.
func glyphClass(table: #null const [..] u8, offset: u64, glyph: u16)->u16 fail
{
    let format = readU16(table, offset)
    if format == 1
    {
        let startGlyph = readU16(table, offset + 2)
        let count      = readU16(table, offset + 4)
        if glyph < startGlyph or cast(u32) glyph - startGlyph >= count do
            return 0
        return readU16(table, offset + 6 + cast(u64) (glyph - startGlyph) * 2)
    }

    if format != 2 do
        return 0

    let rangeCount = readU16(table, offset + 2)
    var left       = 0'u32
    var right      = cast(u32) rangeCount

    while left < right
    {
        let mid        = left + (right - left) / 2
        let base       = offset + 4 + cast(u64) mid * 6
        let startGlyph = readU16(table, base + 0)
        let endGlyph   = readU16(table, base + 2)
        if glyph < startGlyph
        {
            right = mid
            continue
        }

        if glyph > endGlyph
        {
            left = mid + 1
            continue
        }

        return readU16(table, base + 4)
    }

    return 0
}

// Collects every lookup index the GPOS 'kern' feature references.
//
// A font declares the feature once per script and language system, so the same
// indices arrive many times over; the result holds each of them once.
func collectKernLookups(table: #null const [..] u8, featureListOffset: u64)->Array'u16 fail
{
    var result: retval

    let featureCount = readU16(table, featureListOffset)
    for featureCount
    {
        let record = featureListOffset + 2 + cast(u64) @index * 6
        if readU32(table, record) != TAG_KERN do
            continue

        let feature     = featureListOffset + cast(u64) readU16(table, record + 4)
        let lookupCount = readU16(table, feature + 2)
        for lookupCount
        {
            let lookupIndex = readU16(table, feature + 4 + cast(u64) @index * 2)
            if !result.contains(lookupIndex) do
                result.add(lookupIndex)
        }
    }

    return result
}

// Collects the pair-adjustment subtables the GPOS 'kern' feature reaches.
//
// Only the lookups that feature names are kept, so mark attachment and contextual
// positioning are left to a future shaper. A face declaring none keeps an empty
// list and falls back to the legacy 'kern' table.
func parseGpos(faceData: *FaceImpl) fail
{
    let rec = findTable(faceData, TAG_GPOS)
    if !rec do
        return

    let r     = rec!
    let table = getSlice(faceData.fontData.toSlice(), r.offset, r.length)
    if @countof(table) < 10 do
        return

    let featureListOffset = cast(u64) readU16(table, 6)
    let lookupListOffset  = cast(u64) readU16(table, 8)
    let lookupCount       = readU16(table, lookupListOffset)
    let kernLookups       = collectKernLookups(table, featureListOffset)

    for it in kernLookups
    {
        if it >= lookupCount do
            continue

        let lookup        = lookupListOffset + cast(u64) readU16(table, lookupListOffset + 2 + cast(u64) it * 2)
        let lookupType    = readU16(table, lookup)
        let subTableCount = readU16(table, lookup + 4)

        for subTableCount
        {
            var subTable = lookup + cast(u64) readU16(table, lookup + 6 + cast(u64) @index * 2)
            var kind     = lookupType

            // An extension subtable names the real type and a 32-bit offset to it,
            // measured from the extension subtable itself.
            if kind == GPOS_LOOKUP_EXTENSION
            {
                kind     = readU16(table, subTable + 2)
                subTable += cast(u64) readU32(table, subTable + 4)
            }

            if kind == GPOS_LOOKUP_PAIR do
                faceData.gposPairSubtables.add(cast(u32) subTable)
        }
    }

    if faceData.gposPairSubtables.count != 0 do
        faceData.gposTable = table
}

// Searches one format-1 pair set, whose records are sorted by second glyph.
func lookupPairSet(table: #null const [..] u8, pairSet: u64, rightGlyph: u16, recordSize: u64, advanceOffset: u64)->s16 fail
{
    let pairCount = readU16(table, pairSet)
    var left      = 0'u32
    var right     = cast(u32) pairCount

    while left < right
    {
        let mid    = left + (right - left) / 2
        let record = pairSet + 2 + cast(u64) mid * recordSize
        let second = readU16(table, record)
        if rightGlyph < second
        {
            right = mid
            continue
        }

        if rightGlyph > second
        {
            left = mid + 1
            continue
        }

        return readS16(table, record + 2 + advanceOffset)
    }

    return 0
}

// Returns the horizontal advance the GPOS 'kern' feature adds between two glyphs,
// in font design units.
//
// The first subtable declaring a non-zero adjustment answers; a covered pair whose
// adjustment is zero is a deliberate "no kerning here", so the search continues.
func lookupGposKerning(faceData: const *FaceImpl, leftGlyph, rightGlyph: u16)->s16 fail
{
    let table = faceData.gposTable

    for it in faceData.gposPairSubtables
    {
        let subTable = cast(u64) it
        let format   = readU16(table, subTable + 0)
        let coverage = coverageIndex(table, subTable + cast(u64) readU16(table, subTable + 2), leftGlyph)
        if coverage < 0 do
            continue

        let valueFormat1 = readU16(table, subTable + 4)
        let valueFormat2 = readU16(table, subTable + 6)
        let advanceOff   = xAdvanceOffset(valueFormat1)
        if advanceOff < 0 do
            continue

        var value = 0's16
        if format == 1
        {
            // One explicit pair set per covered first glyph, indexed by coverage. A
            // coverage table longer than that array would otherwise read past its end.
            if cast(u32) coverage >= readU16(table, subTable + 8) do
                continue

            let pairSet    = subTable + cast(u64) readU16(table, subTable + 10 + cast(u64) coverage * 2)
            let recordSize = 2 + valueRecordSize(valueFormat1) + valueRecordSize(valueFormat2)
            value = lookupPairSet(table, pairSet, rightGlyph, recordSize, cast(u64) advanceOff)
        }
        elif format == 2
        {
            // A class matrix: each side of the pair reduces to one class, and the
            // two classes index a dense row-major array of value records.
            let class1      = glyphClass(table, subTable + cast(u64) readU16(table, subTable + 8), leftGlyph)
            let class2      = glyphClass(table, subTable + cast(u64) readU16(table, subTable + 10), rightGlyph)
            let class1Count = readU16(table, subTable + 12)
            let class2Count = readU16(table, subTable + 14)
            if class1 >= class1Count or class2 >= class2Count do
                continue

            let recordSize = valueRecordSize(valueFormat1) + valueRecordSize(valueFormat2)
            let record     = subTable + 16 + (cast(u64) class1 * class2Count + class2) * recordSize
            value = readS16(table, record + cast(u64) advanceOff)
        }

        if value != 0 do
            return value
    }

    return 0
}
