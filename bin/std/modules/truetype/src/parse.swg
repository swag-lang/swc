using Swag, Core

const NAME_ID_FAMILY = 1'u16
const NAME_ID_STYLE  = 2'u16

// What a face is called when its 'name' table declares no record this module can
// read. Both are reported like any other name, so a caller never sees an empty one.
const DEFAULT_FAMILY_NAME = "Unknown"
const DEFAULT_STYLE_NAME  = "Regular"

func scoreNameRecord(platformID, encodingID, languageID: u16)->s32
{
    var score = 0
    if platformID == 3
    {
        score += 40
        if encodingID == 10 do
            score += 20
        elif encodingID == 1 do
            score += 15
        if languageID == 0x0409 do
            score += 10
    }
    elif platformID == 0
    {
        score += 30
    }
    elif platformID == 1
    {
        score += 10
    }

    return score
}

func decodeNameRecord(nameTable: #null const [..] u8, stringOffset, recordOffset: u64)->String fail
{
    let platformID = readU16(nameTable, recordOffset + 0)
    let length     = readU16(nameTable, recordOffset + 8)
    let offset     = readU16(nameTable, recordOffset + 10)
    let raw        = getSlice(nameTable, stringOffset + offset, length)

    if platformID == 0 or platformID == 3
    {
        if (@countof(raw) & 1) != 0 do
            fault(0x91)

        var chars: Array'u16
        chars.resize(@countof(raw) / 2)
        for chars.count do
            chars[@index] = readU16(raw, cast(u64) @index * 2)
        return Utf8.fromUtf16(chars.toSlice())
    }

    return String.from(cast(#null string) raw)
}

// Decodes the best-scoring record a 'name' table holds for 'nameID', or an empty
// string when it declares none this module can read.
func decodeBestName(nameTable: #null const [..] u8, nameID: u16)->String fail
{
    var result: retval

    let count        = readU16(nameTable, 2)
    let stringOffset = readU16(nameTable, 4)
    var bestScore    = -1

    for count
    {
        let base = 6'u64 + cast(u64) @index * 12
        if readU16(nameTable, base + 6) != nameID do
            continue

        let platformID = readU16(nameTable, base + 0)
        let encodingID = readU16(nameTable, base + 2)
        let languageID = readU16(nameTable, base + 4)
        let score      = scoreNameRecord(platformID, encodingID, languageID)
        if score <= bestScore do
            continue

        result    = decodeNameRecord(nameTable, stringOffset, base)
        bestScore = score
    }

    return result
}

func parseNames(faceData: *FaceImpl, fallbackFamilyName: string) fail
{
    let defaultStyle = String.from(DEFAULT_STYLE_NAME)
    let rec = findTable(faceData, TAG_NAME)
    if !rec
    {
        if !@countof(fallbackFamilyName) do
            fault(0x91)
        faceData.face.setNames(String.from(fallbackFamilyName), defaultStyle)
        return
    }

    let nameTable = getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)

    var familyName = decodeBestName(nameTable, NAME_ID_FAMILY)
    var styleName  = decodeBestName(nameTable, NAME_ID_STYLE)
    if familyName.length == 0 do
        familyName = String.from(@countof(fallbackFamilyName) ? fallbackFamilyName : DEFAULT_FAMILY_NAME)
    if styleName.length == 0 do
        styleName = defaultStyle
    faceData.face.setNames(familyName, styleName)
}

func parsePost(faceData: *FaceImpl, allowMissing: bool) fail
{
    let rec = findTable(faceData, TAG_POST)
    if !rec
    {
        if allowMissing do
            return
        fault(0x94)
    }

    let record    = rec!
    let postTable = getSlice(faceData.fontData.toSlice(), record.offset, record.length)
    let format    = readU32(postTable, 0)
    if format != 0x00010000 and format != 0x00020000 and format != 0x00025000 and format != 0x00030000 do
        fault(0x9A)

    faceData.face.setUnderline(readS16(postTable, 8), readS16(postTable, 10))
}

// Parse x-height / cap-height from OS/2 (version >= 2). Missing or older tables
// leave them at 0, which disables vertical hinting for that face.
func parseOS2(faceData: *FaceImpl) fail
{
    let rec = findTable(faceData, TAG_OS2)
    if !rec do
        return

    let table = getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
    if @countof(table) < 4 do
        return

    let version = readU16(table, 0)
    if version >= 2 and @countof(table) >= 90
    {
        faceData.xHeight   = readS16(table, 86)
        faceData.capHeight = readS16(table, 88)
        faceData.face.setVerticalZones(faceData.xHeight, faceData.capHeight)
    }
}

// Selects the richest character map the face declares.
//
// A rendering-only subset may legally omit the table entirely: a document that embeds one
// addresses its glyphs by index or through its own encoding, and never asks the font what
// character a glyph stands for. Such a face simply answers no character lookup.
func parseCMap(faceData: *FaceImpl, allowMissing: bool) fail
{
    let record = findTable(faceData, TAG_CMAP)
    if !record
    {
        if allowMissing do
            return
        fault(0x92)
    }

    let table     = record!
    let cmapTable = getSlice(faceData.fontData.toSlice(), table.offset, table.length)
    let count     = readU16(cmapTable, 2)

    var bestSlice: #null const [..] u8
    var bestScore = -1
    var bestFmt   = 0'u16

    for count
    {
        let base       = 4'u64 + cast(u64) @index * 8
        let platformID = readU16(cmapTable, base + 0)
        let encodingID = readU16(cmapTable, base + 2)
        let offset     = readU32(cmapTable, base + 4)
        let subTable   = getSlice(cmapTable, offset, @countof(cmapTable) - offset)
        let format     = readU16(subTable, 0)

        // Variation sequences supplement the selected map rather than compete with
        // it: they resolve a base character already mapped elsewhere.
        if format == 14
        {
            faceData.variationCMap = subTable
            continue
        }

        let formatScore = scoreCMapFormat(format)
        if formatScore < 0 do
            continue

        let score = formatScore + scoreNameRecord(platformID, encodingID, 0)
        if score > bestScore
        {
            bestSlice = subTable
            bestScore = score
            bestFmt   = format
            faceData.face.selectCharMap(platformID, encodingID)
        }
    }

    if bestScore < 0
    {
        if allowMissing do
            return
        fault(0x96)
    }

    faceData.chosenCMap = bestSlice!
    faceData.cmapFormat = bestFmt
    faceData.hasCMap    = true
}

func buildGlyphMetrics(faceData: *FaceImpl) fail
{
    let hmtx = getTableSlice(faceData, TAG_HMTX, 0x93)
    faceData.glyphMetrics.resize(faceData.face.glyphCount)

    var lastAdvance = 0'u16
    for faceData.face.glyphCount
    {
        var metric: GlyphMetric
        if @index < faceData.numLongMetrics
        {
            let base = cast(u64) @index * 4
            metric.advanceWidth    = readU16(hmtx, base + 0)
            metric.leftSideBearing = readS16(hmtx, base + 2)
            lastAdvance            = metric.advanceWidth
        }
        else
        {
            let base = cast(u64) faceData.numLongMetrics * 4 + cast(u64) (@index - faceData.numLongMetrics) * 2
            metric.advanceWidth    = lastAdvance
            metric.leftSideBearing = readS16(hmtx, base)
        }

        faceData.glyphMetrics[@index] = metric
    }
}

func buildGlyphLocations(faceData: *FaceImpl) fail
{
    let loca = getTableSlice(faceData, TAG_LOCA, 0x90)
    faceData.glyphLocations.resize(faceData.face.glyphCount + 1)

    if faceData.indexToLocFormat == 0
    {
        for faceData.glyphLocations.count do
            faceData.glyphLocations[@index] = cast(u32) readU16(loca, cast(u64) @index * 2) * 2
    }
    else
    {
        for faceData.glyphLocations.count do
            faceData.glyphLocations[@index] = readU32(loca, cast(u64) @index * 4)
    }
}

// Parse the legacy 'kern' table, keeping horizontal format-0 subtables only.
// Missing or unsupported tables simply leave the kerning map empty.
func parseKern(faceData: *FaceImpl) fail
{
    let rec = findTable(faceData, TAG_KERN)
    if !rec do
        return

    let table = getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
    if @countof(table) < 4 do
        return

    let nTables = readU16(table, 2)
    var offset  = 4'u64

    for nTables
    {
        if offset + 6 > @countof(table) do
            break

        let length     = readU16(table, offset + 2)
        let coverage   = readU16(table, offset + 4)
        let format     = coverage >> 8     // high byte: subtable format
        let horizontal = (coverage & 0x0001) != 0

        // Only horizontal format-0 pair tables; skip minimum/cross-stream variants.
        if format == 0 and horizontal and (coverage & 0x0002) == 0
        {
            let nPairs  = readU16(table, offset + 6)
            var pairOff = offset + 14     // after nPairs/searchRange/entrySelector/rangeShift
            for nPairs
            {
                if pairOff + 6 > @countof(table) do
                    break
                let left  = readU16(table, pairOff + 0)
                let right = readU16(table, pairOff + 2)
                let value = readS16(table, pairOff + 4)
                if value != 0
                {
                    let key = (cast(u32) left << 16) | cast(u32) right
                    faceData.kernPairs.add(key, value)
                }

                pairOff += 6
            }
        }

        if length == 0 do
            break
        offset += length
    }
}

func initFaceRecords(faceData: *FaceImpl)
{
    faceData.face.initializeRecords()
}

// Rejects an offset table this module cannot read, naming the container it found
// instead of reporting every one of them as an unknown format.
func checkSfntVersion(data: #null const [..] u8, offset: u64) fail
{
    let tag = readU32(data, offset)
    if tag == TAG_WOFF or tag == TAG_WOF2 do
        fault(0x0E)
    if tag != TAG_SFNT and tag != TAG_TRUE and tag != TAG_OTTO do
        fault(0x02)
}

// Returns how many faces the font data holds: the face count of a `ttcf`
// collection, and one for a bare font file.
func countFacesIn(data: #null const [..] u8)->u32 fail
{
    if @countof(data) < 12 do
        fault(0x02)
    if readU32(data, 0) == TAG_TTCF do
        return readU32(data, 8)

    checkSfntVersion(data, 0)
    return 1
}

// Returns the offset of the offset table 'faceIndex' selects.
//
// A collection stores one such offset per face after a twelve-byte header; every
// table record inside a member still addresses the whole file, so only the
// directory moves.
func findFaceOffset(data: #null const [..] u8, faceIndex: u32)->u64 fail
{
    if @countof(data) < 12 do
        fault(0x02)

    var offset = 0'u64
    if readU32(data, 0) == TAG_TTCF
    {
        if faceIndex >= readU32(data, 8) do
            fault(0x0F)
        offset = cast(u64) readU32(data, 12 + cast(u64) faceIndex * 4)
    }
    elif faceIndex != 0
    {
        fault(0x0F)
    }

    checkSfntVersion(data, offset)
    return offset
}

// Locates one table of the directory at 'faceOffset', without building a face.
func findTableAt(data: #null const [..] u8, faceOffset: u64, tag: u32)->#null const [..] u8 fail
{
    let numTables = readU16(data, faceOffset + 4)
    for numTables
    {
        let base = faceOffset + 12 + cast(u64) @index * 16
        if readU32(data, base) != tag do
            continue
        return getSlice(data, readU32(data, base + 8), readU32(data, base + 12))
    }

    return null
}

// Returns the family name one face of a font file declares.
//
// Only the offset table and the 'name' table are read, which is what lets a
// collection be searched for a family without loading each of its faces in turn.
func familyNameIn(data: #null const [..] u8, faceIndex: u32)->String fail
{
    let faceOffset = findFaceOffset(data, faceIndex)
    let nameTable  = findTableAt(data, faceOffset, TAG_NAME)
    if !nameTable do
        fault(0x91)

    let familyName = decodeBestName(nameTable, NAME_ID_FAMILY)
    if familyName.length == 0 do
        return DEFAULT_FAMILY_NAME
    return familyName
}

// Fills the per-glyph advances of a PostScript face from its charstrings.
//
// A bare CFF or Type 1 program ships no `hmtx`, and the advance of a charstring glyph is
// stated inside the charstring itself. Resolving it stops at the first stack-clearing
// operator, so this costs a fraction of interpreting the outline.
func buildCharstringMetrics(faceData: *FaceImpl) fail
{
    let glyphCount = faceData.face.glyphCount
    faceData.glyphMetrics.resize(glyphCount)

    for gid in glyphCount
    {
        var width = 0.0'f64
        if faceData.outlineSource == .Cff do
            width = runType2Charstring(&faceData.cff, gid, null)
        else do
            width = runType1Charstring(&faceData.type1, gid, null)

        var metric: GlyphMetric
        metric.advanceWidth       = cast(u16) Math.clamp(Math.round(width), 0.0, cast(f64) Swag.U16.Max)
        faceData.glyphMetrics[gid] = metric
    }
}

// Builds a Unicode map for a font program that ships none of its own.
//
// The font's built-in encoding says which glyph each code selects, and StandardEncoding
// says which character that code stands for; together they answer a character lookup
// without inventing a mapping the font never declared.
func buildSyntheticCMap(faceData: *FaceImpl)
{
    for code in 256'u32
    {
        let gid = faceData.glyphIndexByCode(code)
        if !gid do
            continue
        let value = standardEncodingRune(cast(u8) code)
        if value and !faceData.syntheticCMap.contains(cast(u32) value) do
            faceData.syntheticCMap.add(cast(u32) value, gid)
    }

    // A subset that names its glyphs by code point still resolves, which is the convention
    // a document writer falls back to when no standard name fits.
    let names = faceData.outlineSource == .Cff ? &faceData.cff.glyphNames : &faceData.type1.glyphNames
    for name, gid in names
    {
        let value = glyphNameRune(name.toString())
        if value and !faceData.syntheticCMap.contains(cast(u32) value) do
            faceData.syntheticCMap.add(cast(u32) value, cast(u32) gid)
    }
}

// Builds a face around a font program that carries no sfnt wrapper.
//
// PDF hands a bare CFF or Type 1 program straight from the file, so every metric an
// OpenType face would read from a table has to come from the program's own header.
func parseProgramFace(faceData: *FaceImpl, fallbackFamilyName: string) fail
{
    let data = faceData.fontData.toSlice()
    var name: String
    var italic = false
    var bold   = false

    if faceData.outlineSource == .Cff
    {
        faceData.cff = parseCffFont(data)
        faceData.unitsPerEm = faceData.cff.unitsPerEm
        faceData.face.setGlyphCount(faceData.cff.charStrings.count())
        faceData.face.setHeader(faceData.unitsPerEm, faceData.cff.xMin, faceData.cff.yMin, faceData.cff.xMax, faceData.cff.yMax)
        name   = faceData.cff.fontName
        italic = faceData.cff.italic
        bold   = faceData.cff.bold
    }
    else
    {
        faceData.type1 = parseType1Font(data)
        faceData.unitsPerEm = faceData.type1.unitsPerEm
        faceData.face.setGlyphCount(cast(u32) faceData.type1.charstrings.count)
        faceData.face.setHeader(faceData.unitsPerEm, faceData.type1.xMin, faceData.type1.yMin, faceData.type1.xMax, faceData.type1.yMax)
        name   = faceData.type1.fontName
        italic = faceData.type1.italic
        bold   = faceData.type1.bold
    }

    if !faceData.face.glyphCount do
        fault(0xBA)

    // The design bounding box is the only vertical information such a program states, and
    // it is what a renderer needs a line height for.
    let ascender  = cast(s16) faceData.face.bbox.yMax
    let descender = cast(s16) faceData.face.bbox.yMin
    faceData.face.setHorizontalMetrics(ascender, descender, 0, cast(s16) faceData.face.bbox.xMax)

    if !name.length do
        name = String.from(@countof(fallbackFamilyName) ? fallbackFamilyName : DEFAULT_FAMILY_NAME)
    faceData.face.setNames(name, String.from(DEFAULT_STYLE_NAME))
    faceData.face.setUnderline(cast(s16) -(cast(s32) faceData.unitsPerEm / 10), cast(s16) (faceData.unitsPerEm / 20))

    var style = StyleFlag.None
    if bold do
        style |= .Bold
    if italic do
        style |= .Italic
    faceData.face.setStyle(style)

    buildCharstringMetrics(faceData)
    buildSyntheticCMap(faceData)
    initFaceRecords(faceData)
}

func parseFace(faceData: *FaceImpl, faceIndex: u32, fallbackFamilyName: string = "") fail
{
    let data       = faceData.fontData.toSlice()
    let faceOffset = findFaceOffset(data, faceIndex)

    let numTables = readU16(data, faceOffset + 4)
    faceData.tables.resize(numTables)

    for numTables
    {
        let base = faceOffset + 12 + cast(u64) @index * 16
        faceData.tables[@index].tag    = readU32(data, base + 0)
        faceData.tables[@index].offset = readU32(data, base + 8)
        faceData.tables[@index].length = readU32(data, base + 12)
    }

    let cffTable = findTable(faceData, TAG_CFF)
    if cffTable do
        faceData.outlineSource = .Cff

    let head = getTableSlice(faceData, TAG_HEAD, 0x8E)
    if @countof(head) < 54 do
        fault(0xB9)

    faceData.unitsPerEm = readU16(head, 18)
    faceData.face.setHeader(faceData.unitsPerEm, readS16(head, 36), readS16(head, 38), readS16(head, 40), readS16(head, 42))
    faceData.macStyle         = readU16(head, 44)
    faceData.indexToLocFormat = readS16(head, 50)

    let hhea = getTableSlice(faceData, TAG_HHEA, 0x8F)
    if @countof(hhea) < 36 do
        fault(0x8F)

    let ascender  = readS16(hhea, 4)
    let descender = readS16(hhea, 6)
    faceData.lineGap = readS16(hhea, 8)
    faceData.face.setHorizontalMetrics(ascender, descender, faceData.lineGap, readS16(hhea, 10))
    faceData.numLongMetrics = readU16(hhea, 34)

    let maxp = getTableSlice(faceData, TAG_MAXP, 0x8E)
    if @countof(maxp) < 6 do
        fault(0x8E)

    faceData.face.setGlyphCount(readU16(maxp, 4))

    buildGlyphMetrics(faceData)

    // A CFF-flavoured OpenType file keeps its outlines in charstrings, so it has neither
    // `glyf` nor the `loca` index into it; everything else it declares is unchanged.
    if faceData.outlineSource == .Cff
    {
        let record = cffTable!
        faceData.cff = parseCffFont(getSlice(data, record.offset, record.length))
    }
    else
    {
        buildGlyphLocations(faceData)
    }

    let isSubset = @countof(fallbackFamilyName) != 0
    parseCMap(faceData, isSubset)
    if !faceData.hasCMap and faceData.outlineSource == .Cff do
        buildSyntheticCMap(faceData)
    parseNames(faceData, fallbackFamilyName)
    parsePost(faceData, isSubset or faceData.outlineSource == .Cff)
    parseKern(faceData)
    parseGpos(faceData)
    parseOS2(faceData)

    var style = StyleFlag.None
    if (faceData.macStyle & 0x0001) != 0 or faceData.face.styleName.contains(cast(string) "Bold") do
        style |= .Bold
    if (faceData.macStyle & 0x0002) != 0 or faceData.face.styleName.contains(cast(string) "Italic") do
        style |= .Italic
    faceData.face.setStyle(style)

    initFaceRecords(faceData)
}
