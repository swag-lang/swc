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

func decodeNameRecord(nameTable: const [..] u8?, stringOffset, recordOffset: u64)->String fail
{
    let platformID = try readU16(nameTable, recordOffset + 0)
    let length     = try readU16(nameTable, recordOffset + 8)
    let offset     = try readU16(nameTable, recordOffset + 10)
    let raw        = try getSlice(nameTable, stringOffset + offset, length)

    if platformID == 0 or platformID == 3
    {
        if (raw.count & 1) != 0 do
            try fault(0x91)

        var chars: Array'u16
        chars.resize(raw.count / 2)
        for index in chars.count do
            chars[index] = try readU16(raw, cast(u64) index * 2)
        return Utf8.fromUtf16(chars.toSlice())
    }

    return String.from(cast(string?) raw)
}

// Decodes the best-scoring record a 'name' table holds for 'nameID', or an empty
// string when it declares none this module can read.
func decodeBestName(nameTable: const [..] u8?, nameID: u16)->String fail
{
    var result: retval

    let count        = try readU16(nameTable, 2)
    let stringOffset = try readU16(nameTable, 4)
    var bestScore    = -1

    for index in count
    {
        let base = 6'u64 + cast(u64) index * 12
        if try readU16(nameTable, base + 6) != nameID do
            continue

        let platformID = try readU16(nameTable, base + 0)
        let encodingID = try readU16(nameTable, base + 2)
        let languageID = try readU16(nameTable, base + 4)
        let score      = scoreNameRecord(platformID, encodingID, languageID)
        if score <= bestScore do
            continue

        result    = try decodeNameRecord(nameTable, stringOffset, base)
        bestScore = score
    }

    return result
}

func parseNames(faceData: *FaceImpl, fallbackFamilyName: string) fail
{
    let defaultStyle = String.from(DEFAULT_STYLE_NAME)
    let rec = findTable(faceData, TAG_NAME)
    if not rec
    {
        if not fallbackFamilyName.count do
            try fault(0x91)
        faceData.face.setNames(String.from(fallbackFamilyName), defaultStyle)
        return
    }

    let nameTable = try getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)

    var familyName = try decodeBestName(nameTable, NAME_ID_FAMILY)
    var styleName  = try decodeBestName(nameTable, NAME_ID_STYLE)
    if familyName.length == 0 do
        familyName = String.from(fallbackFamilyName.count ? fallbackFamilyName : DEFAULT_FAMILY_NAME)
    if styleName.length == 0 do
        styleName = defaultStyle
    faceData.face.setNames(familyName, styleName)
}

func parsePost(faceData: *FaceImpl, allowMissing: bool) fail
{
    let rec = findTable(faceData, TAG_POST)
    if not rec
    {
        if allowMissing do
            return
        try fault(0x94)
    }

    let record    = rec!
    let postTable = try getSlice(faceData.fontData.toSlice(), record.offset, record.length)
    let format    = try readU32(postTable, 0)
    if format != 0x00010000 and format != 0x00020000 and format != 0x00025000 and format != 0x00030000 do
        try fault(0x9A)

    faceData.face.setUnderline(try readS16(postTable, 8), try readS16(postTable, 10))
}

// Parse x-height / cap-height from OS/2 (version >= 2). Missing or older tables
// leave them at 0, which disables vertical hinting for that face.
func parseOS2(faceData: *FaceImpl) fail
{
    let rec = findTable(faceData, TAG_OS2)
    if not rec do
        return

    let table = try getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
    if table.count < 4 do
        return

    let version = try readU16(table, 0)
    if version >= 2 and table.count >= 90
    {
        faceData.xHeight   = try readS16(table, 86)
        faceData.capHeight = try readS16(table, 88)
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
    if not record
    {
        if allowMissing do
            return
        try fault(0x92)
    }

    let table     = record!
    let cmapTable = try getSlice(faceData.fontData.toSlice(), table.offset, table.length)
    let count     = try readU16(cmapTable, 2)

    var bestSlice: const [..] u8?
    var bestScore = -1
    var bestFmt   = 0'u16

    for index in count
    {
        let base       = 4'u64 + cast(u64) index * 8
        let platformID = try readU16(cmapTable, base + 0)
        let encodingID = try readU16(cmapTable, base + 2)
        let offset     = try readU32(cmapTable, base + 4)
        let subTable   = try getSlice(cmapTable, offset, cmapTable.count - offset)
        let format     = try readU16(subTable, 0)

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
        try fault(0x96)
    }

    faceData.chosenCMap = bestSlice!
    faceData.cmapFormat = bestFmt
    faceData.hasCMap    = true
}

func buildGlyphMetrics(faceData: *FaceImpl) fail
{
    let hmtx = try getTableSlice(faceData, TAG_HMTX, 0x93)
    faceData.glyphMetrics.resize(faceData.face.glyphCount)

    var lastAdvance = 0'u16
    for index in faceData.face.glyphCount
    {
        var metric: GlyphMetric
        if index < faceData.numLongMetrics
        {
            let base = cast(u64) index * 4
            metric.advanceWidth    = try readU16(hmtx, base + 0)
            metric.leftSideBearing = try readS16(hmtx, base + 2)
            lastAdvance            = metric.advanceWidth
        }
        else
        {
            let base = cast(u64) faceData.numLongMetrics * 4 + cast(u64) (index - faceData.numLongMetrics) * 2
            metric.advanceWidth    = lastAdvance
            metric.leftSideBearing = try readS16(hmtx, base)
        }

        faceData.glyphMetrics[index] = metric
    }
}

func buildGlyphLocations(faceData: *FaceImpl) fail
{
    let loca = try getTableSlice(faceData, TAG_LOCA, 0x90)
    faceData.glyphLocations.resize(faceData.face.glyphCount + 1)

    if faceData.indexToLocFormat == 0
    {
        for index in faceData.glyphLocations.count do
            faceData.glyphLocations[index] = cast(u32) (try readU16(loca, cast(u64) index * 2)) * 2
    }
    else
    {
        for index in faceData.glyphLocations.count do
            faceData.glyphLocations[index] = try readU32(loca, cast(u64) index * 4)
    }
}

// Parse the legacy 'kern' table, keeping horizontal format-0 subtables only.
// Missing or unsupported tables simply leave the kerning map empty.
func parseKern(faceData: *FaceImpl) fail
{
    let rec = findTable(faceData, TAG_KERN)
    if not rec do
        return

    let table = try getSlice(faceData.fontData.toSlice(), rec.offset, rec.length)
    if table.count < 4 do
        return

    let nTables = try readU16(table, 2)
    var offset  = 4'u64

    for nTables
    {
        if offset + 6 > table.count do
            break

        let length     = try readU16(table, offset + 2)
        let coverage   = try readU16(table, offset + 4)
        let format     = coverage >> 8     // high byte: subtable format
        let horizontal = (coverage & 0x0001) != 0

        // Only horizontal format-0 pair tables; skip minimum/cross-stream variants.
        if format == 0 and horizontal and (coverage & 0x0002) == 0
        {
            let nPairs  = try readU16(table, offset + 6)
            var pairOff = offset + 14     // after nPairs/searchRange/entrySelector/rangeShift
            for nPairs
            {
                if pairOff + 6 > table.count do
                    break
                let left  = try readU16(table, pairOff + 0)
                let right = try readU16(table, pairOff + 2)
                let value = try readS16(table, pairOff + 4)
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
func checkSfntVersion(data: const [..] u8?, offset: u64) fail
{
    let tag = try readU32(data, offset)
    if tag == TAG_WOFF or tag == TAG_WOF2 do
        try fault(0x0E)
    if tag != TAG_SFNT and tag != TAG_TRUE and tag != TAG_OTTO do
        try fault(0x02)
}

// Returns how many faces the font data holds: the face count of a `ttcf`
// collection, and one for a bare font file.
func countFacesIn(data: const [..] u8?)->u32 fail
{
    if data.count < 12 do
        try fault(0x02)
    if try readU32(data, 0) == TAG_TTCF do
        return try readU32(data, 8)

    try checkSfntVersion(data, 0)
    return 1
}

// Returns the offset of the offset table 'faceIndex' selects.
//
// A collection stores one such offset per face after a twelve-byte header; every
// table record inside a member still addresses the whole file, so only the
// directory moves.
func findFaceOffset(data: const [..] u8?, faceIndex: u32)->u64 fail
{
    if data.count < 12 do
        try fault(0x02)

    var offset = 0'u64
    if try readU32(data, 0) == TAG_TTCF
    {
        if faceIndex >= try readU32(data, 8) do
            try fault(0x0F)
        offset = cast(u64) (try readU32(data, 12 + cast(u64) faceIndex * 4))
    }
    elif faceIndex != 0
    {
        try fault(0x0F)
    }

    try checkSfntVersion(data, offset)
    return offset
}

// Locates one table of the directory at 'faceOffset', without building a face.
func findTableAt(data: const [..] u8?, faceOffset: u64, tag: u32)->const [..] u8? fail
{
    let numTables = try readU16(data, faceOffset + 4)
    for index in numTables
    {
        let base = faceOffset + 12 + cast(u64) index * 16
        if try readU32(data, base) != tag do
            continue
        return try getSlice(data, try readU32(data, base + 8), try readU32(data, base + 12))
    }

    return null
}

// Returns the family name one face of a font file declares.
//
// Only the offset table and the 'name' table are read, which is what lets a
// collection be searched for a family without loading each of its faces in turn.
func familyNameIn(data: const [..] u8?, faceIndex: u32)->String fail
{
    let faceOffset = try findFaceOffset(data, faceIndex)
    let nameTable  = try findTableAt(data, faceOffset, TAG_NAME)
    if not nameTable do
        try fault(0x91)

    let familyName = try decodeBestName(nameTable, NAME_ID_FAMILY)
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
            width = try runType2Charstring(&faceData.cff, gid, null)
        else do
            width = try runType1Charstring(&faceData.type1, gid, null)

        var metric: GlyphMetric
        metric.advanceWidth        = cast(u16) Math.clamp(Math.round(width), 0.0, cast(f64) Swag.U16.Max)
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
        if not gid do
            continue
        let value = standardEncodingRune(cast(u8) code)
        if value and not faceData.syntheticCMap.contains(cast(u32) value) do
            faceData.syntheticCMap.add(cast(u32) value, gid)
    }

    // A subset that names its glyphs by code point still resolves, which is the convention
    // a document writer falls back to when no standard name fits.
    let names = faceData.outlineSource == .Cff ? &faceData.cff.glyphNames : &faceData.type1.glyphNames
    for name, gid in names
    {
        let value = glyphNameRune(name.toString())
        if value and not faceData.syntheticCMap.contains(cast(u32) value) do
            faceData.syntheticCMap.add(cast(u32) value, cast(u32) gid)
    }
}

// Builds a face around a font program that carries no sfnt wrapper.
//
// PDF hands a bare CFF or Type 1 program straight from the file, so every metric an
// OpenType face would read from a table has to come from the program's own header.
func parseProgramFace(faceData: *FaceImpl, fallbackFamilyName: string) fail
{
    let data   = faceData.fontData.toSlice()
    var name: String
    var italic = false
    var bold   = false

    if faceData.outlineSource == .Cff
    {
        faceData.cff        = try parseCffFont(data)
        faceData.unitsPerEm = faceData.cff.unitsPerEm
        faceData.face.setGlyphCount(faceData.cff.charStrings.count())
        faceData.face.setHeader(faceData.unitsPerEm, faceData.cff.xMin, faceData.cff.yMin, faceData.cff.xMax, faceData.cff.yMax)
        name   = faceData.cff.fontName
        italic = faceData.cff.italic
        bold   = faceData.cff.bold
    }
    else
    {
        faceData.type1      = try parseType1Font(data)
        faceData.unitsPerEm = faceData.type1.unitsPerEm
        faceData.face.setGlyphCount(cast(u32) faceData.type1.charstrings.count)
        faceData.face.setHeader(faceData.unitsPerEm, faceData.type1.xMin, faceData.type1.yMin, faceData.type1.xMax, faceData.type1.yMax)
        name   = faceData.type1.fontName
        italic = faceData.type1.italic
        bold   = faceData.type1.bold
    }

    if not faceData.face.glyphCount do
        try fault(0xBA)

    // The design bounding box is the only vertical information such a program states, and
    // it is what a renderer needs a line height for.
    let ascender  = cast(s16) faceData.face.bbox.yMax
    let descender = cast(s16) faceData.face.bbox.yMin
    faceData.face.setHorizontalMetrics(ascender, descender, 0, cast(s16) faceData.face.bbox.xMax)

    if not name.length do
        name = String.from(fallbackFamilyName.count ? fallbackFamilyName : DEFAULT_FAMILY_NAME)
    faceData.face.setNames(name, String.from(DEFAULT_STYLE_NAME))
    faceData.face.setUnderline(cast(s16) -(cast(s32) faceData.unitsPerEm / 10), cast(s16) (faceData.unitsPerEm / 20))

    var style = StyleFlag.None
    if bold do
        style |= .Bold
    if italic do
        style |= .Italic
    faceData.face.setStyle(style)

    try buildCharstringMetrics(faceData)
    buildSyntheticCMap(faceData)
    initFaceRecords(faceData)
}

func parseFace(faceData: *FaceImpl, faceIndex: u32, fallbackFamilyName: string = "") fail
{
    let data       = faceData.fontData.toSlice()
    let faceOffset = try findFaceOffset(data, faceIndex)

    let numTables = try readU16(data, faceOffset + 4)
    faceData.tables.resize(numTables)

    for idx in numTables
    {
        let base = faceOffset + 12 + cast(u64) idx * 16
        faceData.tables[idx].tag    = try readU32(data, base + 0)
        faceData.tables[idx].offset = try readU32(data, base + 8)
        faceData.tables[idx].length = try readU32(data, base + 12)
    }

    let cffTable = findTable(faceData, TAG_CFF)
    if cffTable do
        faceData.outlineSource = .Cff

    let head = try getTableSlice(faceData, TAG_HEAD, 0x8E)
    if head.count < 54 do
        try fault(0xB9)

    faceData.unitsPerEm = try readU16(head, 18)
    faceData.face.setHeader(faceData.unitsPerEm, try readS16(head, 36), try readS16(head, 38), try readS16(head, 40), try readS16(head, 42))
    faceData.macStyle         = try readU16(head, 44)
    faceData.indexToLocFormat = try readS16(head, 50)

    let hhea = try getTableSlice(faceData, TAG_HHEA, 0x8F)
    if hhea.count < 36 do
        try fault(0x8F)

    let ascender  = try readS16(hhea, 4)
    let descender = try readS16(hhea, 6)
    faceData.lineGap = try readS16(hhea, 8)
    faceData.face.setHorizontalMetrics(ascender, descender, faceData.lineGap, try readS16(hhea, 10))
    faceData.numLongMetrics = try readU16(hhea, 34)

    let maxp = try getTableSlice(faceData, TAG_MAXP, 0x8E)
    if maxp.count < 6 do
        try fault(0x8E)

    faceData.face.setGlyphCount(try readU16(maxp, 4))

    try buildGlyphMetrics(faceData)

    // A CFF-flavoured OpenType file keeps its outlines in charstrings, so it has neither
    // `glyf` nor the `loca` index into it; everything else it declares is unchanged.
    if faceData.outlineSource == .Cff
    {
        let record = cffTable!
        faceData.cff = try parseCffFont(try getSlice(data, record.offset, record.length))
    }
    else
    {
        try buildGlyphLocations(faceData)
    }

    let isSubset = fallbackFamilyName.count != 0
    try parseCMap(faceData, isSubset)
    if not faceData.hasCMap and faceData.outlineSource == .Cff do
        buildSyntheticCMap(faceData)
    try parseNames(faceData, fallbackFamilyName)
    try parsePost(faceData, isSubset or faceData.outlineSource == .Cff)
    try parseKern(faceData)
    try parseGpos(faceData)
    try parseOS2(faceData)

    var style = StyleFlag.None
    if (faceData.macStyle & 0x0001) != 0 or faceData.face.styleName.contains(cast(string) "Bold") do
        style |= .Bold
    if (faceData.macStyle & 0x0002) != 0 or faceData.face.styleName.contains(cast(string) "Italic") do
        style |= .Italic
    faceData.face.setStyle(style)

    initFaceRecords(faceData)
}
