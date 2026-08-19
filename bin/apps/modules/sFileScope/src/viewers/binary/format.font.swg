#global internal

using Core

// Size of one record of the table directory.
private const FontRecordSize = 16'u64

// Returns whether the file is an sfnt font or a collection of them.
//
// The four spellings of the version are the four families that share the same container: outlines
// as TrueType glyphs, outlines as PostScript curves, an old Apple variant, and a collection.
func isSfntFont(image: *BinaryImage)->bool
{
    image.bigEndian = true
    if image.matches(0, "OTTO") or image.matches(0, "true") or image.matches(0, "ttcf") do
        return true
    return image.u32At(0) == 0x00010000
}

// Adds the table directory of a font, and the names the font calls itself by.
func reportSfntFont(image: *BinaryImage, report: *BinaryReport)
{
    // Everything in an sfnt container is big endian, including the collection header.
    image.bigEndian = true

    let s = binStrings()
    if image.matches(0, "ttcf")
    {
        reportFontCollection(image, report)
        return
    }

    let names = reportFontTables(image, report, 0, open: true)
    report.formatName = String.from(s.font_Font)
    report.summary    = names.isEmpty() ? String.from(s.font_Font) : Format.toString("% · %", s.font_Font, names)
}

private func reportFontCollection(image: *BinaryImage, report: *BinaryReport)
{
    let s     = binStrings()
    let count = cast(u64) image.u32At(8)
    let shown = Math.min(count, BinaryListLimit)
    let total = countText(count, s.word_Entry, s.word_Entries)

    report.beginGroup(s.font_Collection, total.toString(), "", offset: 0, length: 12 + count * 4, open: true)
    let version = Format.toString("%.%", image.u16At(4), image.u16At(6))
    report.field(4, 4, "Version", version.toString())
    report.numField(8, 4, "numFonts", count)

    for index in shown
    {
        let at = cast(u64) image.u32At(12 + index * 4)
        discard reportFontTables(image, report, at, open: false)
    }

    report.listCut(shown, count)
    report.endGroup()

    report.formatName = String.from(s.font_Collection)
    report.summary    = Format.toString("% · %", s.font_Collection, total)
}

// Adds the tables of the font whose directory starts at `at`, and returns the family it names.
private func reportFontTables(image: *BinaryImage, report: *BinaryReport, at: u64, open: bool)->String
{
    var result: retval

    let s     = binStrings()
    let count = cast(u64) image.u16At(at + 4)
    let shown = Math.min(count, BinaryListLimit)
    let total = countText(count, s.word_Entry, s.word_Entries)

    var headAt = Swag.U64.Max
    var maxpAt = Swag.U64.Max
    var nameAt = Swag.U64.Max

    report.beginGroup(s.font_Tables, total.toString(), s.font_TablesDesc, offset: at, length: 12 + count * FontRecordSize, open: open)

    for index in shown
    {
        let entryAt = at + 12 + index * FontRecordSize
        let tag     = image.fixedTextAt(entryAt, 4)
        let tableAt = cast(u64) image.u32At(entryAt + 8)
        let size    = cast(u64) image.u32At(entryAt + 12)
        let stored  = StrConv.toDisplaySize(size)

        if tag == "head" do
            headAt = tableAt
        elif tag == "maxp" do
            maxpAt = tableAt
        elif tag == "name" do
            nameAt = tableAt

        report.beginGroup(tag.toString(), stored.toString(), "", offset: tableAt, length: size)
        report.hexField(entryAt + 4, 4, "checkSum", cast(u64) image.u32At(entryAt + 4))
        report.hexField(entryAt + 8, 4, "offset", tableAt)
        report.sizeField(entryAt + 12, 4, "length", size)
        report.endGroup()
    }

    report.listCut(shown, count)
    report.endGroup()

    if headAt != Swag.U64.Max and image.has(headAt, 54)
    {
        report.numField(headAt + 18, 2, s.font_UnitsPerEm, cast(u64) image.u16At(headAt + 18))
        report.hexField(headAt + 44, 2, "macStyle", cast(u64) image.u16At(headAt + 44))
    }

    if maxpAt != Swag.U64.Max and image.has(maxpAt, 6) do
        report.numField(maxpAt + 4, 2, s.font_Glyphs, cast(u64) image.u16At(maxpAt + 4))

    if nameAt != Swag.U64.Max do
        result = reportFontNames(image, report, nameAt, open)
    return result
}

// Adds the naming table, and returns the family the font calls itself.
private func reportFontNames(image: *BinaryImage, report: *BinaryReport, at: u64, open: bool)->String
{
    var result: retval

    let s         = binStrings()
    let count     = cast(u64) image.u16At(at + 2)
    let stringsAt = at + cast(u64) image.u16At(at + 4)
    let shown     = Math.min(count, BinaryListLimit)
    let total     = countText(count, s.word_Entry, s.word_Entries)

    report.beginGroup(s.font_Names, total.toString(), "", offset: at, length: 6 + count * 12, open: open)

    for index in shown
    {
        let entryAt  = at + 6 + index * 12
        let platform = image.u16At(entryAt)
        let nameId   = image.u16At(entryAt + 6)
        let length   = cast(u64) image.u16At(entryAt + 8)
        let valueAt  = stringsAt + cast(u64) image.u16At(entryAt + 10)

        let label = fontNameLabel(nameId)
        if !@countof(label) do
            continue

        // Windows records every name in UTF-16, and the older platforms in single bytes; the
        // platform identifier is the only thing that says which.
        let text = platform == 3 ? image.wideTextAt(valueAt, length / 2) : image.fixedTextAt(valueAt, length)
        if text.isEmpty() do
            continue

        report.field(valueAt, length, label, text.toString())
        if nameId == 1 and result.isEmpty() do
            result = text
    }

    report.listCut(shown, count)
    report.endGroup()
    return result
}

// Returns which of the naming table's entries are worth showing, and under what heading.
private func fontNameLabel(nameId: u16)->string
{
    let s = binStrings()
    switch nameId
    {
    case 0: return "Copyright"
    case 1: return s.font_Family
    case 2: return s.font_Subfamily
    case 4: return s.font_FullName
    case 5: return s.font_Version
    case 6: return "PostScript"
    case 8: return "Manufacturer"
    case 9: return "Designer"
    }

    return ""
}
