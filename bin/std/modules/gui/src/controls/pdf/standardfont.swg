#global public
#global namespace Pdf

using Core, Core.Math

// One of the fourteen typefaces every PDF consumer provides without an embedded font file.
//
// The module writes text with these faces only, so a document it produces carries no font
// program and stays small. Metrics come from the built-in tables in this file, so text can
// be measured without reading a font from the system.
enum StandardFont
{
    Helvetica                // Sans-serif, regular.
    HelveticaBold            // Sans-serif, bold.
    HelveticaOblique         // Sans-serif, slanted.
    HelveticaBoldOblique     // Sans-serif, bold and slanted.
    TimesRoman               // Serif, regular.
    TimesBold                // Serif, bold.
    TimesItalic              // Serif, italic.
    TimesBoldItalic          // Serif, bold and italic.
    Courier                  // Fixed pitch, regular.
    CourierBold              // Fixed pitch, bold.
    CourierOblique           // Fixed pitch, slanted.
    CourierBoldOblique       // Fixed pitch, bold and slanted.
}

// Advance widths of codes 32 to 126, in 1/1000 of the text size.
//
// The four Courier faces share one fixed advance, and each oblique face has the metrics of
// its upright companion, so twelve faces need six tables.
private const StandardWidthFirst = 32'u32
private const StandardWidthLast = 126'u32
private const CourierWidth = 600'u16

private const HelveticaWidths: [95] u16 = [
    278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
    1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
    333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
    556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584]

private const HelveticaBoldWidths: [95] u16 = [
    278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
    556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
    975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
    667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
    333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
    611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584]

private const TimesRomanWidths: [95] u16 = [
    250, 333, 408, 500, 500, 833, 778, 180, 333, 333, 500, 564, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 278, 278, 564, 564, 564, 444,
    921, 722, 667, 667, 722, 611, 556, 722, 722, 333, 389, 722, 611, 889, 722, 722,
    556, 722, 667, 556, 611, 722, 722, 944, 722, 722, 611, 333, 278, 333, 469, 500,
    333, 444, 500, 444, 500, 444, 333, 500, 500, 278, 278, 500, 278, 778, 500, 500,
    500, 500, 333, 389, 278, 500, 500, 722, 500, 500, 444, 480, 200, 480, 541]

private const TimesBoldWidths: [95] u16 = [
    250, 333, 555, 500, 500, 1000, 833, 278, 333, 333, 500, 570, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500,
    930, 722, 667, 722, 722, 667, 611, 778, 778, 389, 500, 778, 667, 944, 722, 778,
    611, 778, 722, 556, 667, 722, 722, 1000, 722, 722, 667, 333, 278, 333, 581, 500,
    333, 500, 556, 444, 556, 444, 333, 500, 556, 278, 333, 556, 278, 833, 556, 500,
    556, 556, 444, 389, 333, 556, 500, 722, 500, 500, 444, 394, 220, 394, 520]

private const TimesItalicWidths: [95] u16 = [
    250, 333, 420, 500, 500, 833, 778, 214, 333, 333, 500, 675, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 675, 675, 675, 500,
    920, 611, 611, 667, 722, 611, 611, 722, 722, 333, 444, 667, 556, 833, 667, 722,
    611, 722, 611, 500, 556, 722, 611, 833, 611, 556, 556, 389, 278, 389, 422, 500,
    333, 500, 500, 444, 500, 444, 278, 500, 500, 278, 278, 444, 278, 722, 500, 500,
    500, 500, 389, 389, 278, 500, 444, 667, 444, 444, 389, 400, 275, 400, 541]

private const TimesBoldItalicWidths: [95] u16 = [
    250, 389, 555, 500, 500, 833, 778, 278, 333, 333, 500, 570, 250, 333, 250, 278,
    500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 333, 333, 570, 570, 570, 500,
    832, 667, 667, 667, 722, 667, 667, 722, 778, 389, 500, 667, 611, 889, 722, 722,
    611, 722, 667, 556, 611, 722, 667, 889, 667, 611, 611, 333, 278, 333, 570, 500,
    333, 500, 500, 444, 500, 444, 333, 500, 556, 278, 278, 500, 278, 778, 556, 500,
    500, 500, 389, 389, 278, 556, 444, 667, 500, 444, 389, 348, 220, 348, 570]

impl StandardFont
{
    // Returns the `BaseFont` name a PDF font dictionary uses for this face.
    mtd const baseFontName()->string
    {
        switch #complete me
        {
        case .Helvetica:            return "Helvetica"
        case .HelveticaBold:        return "Helvetica-Bold"
        case .HelveticaOblique:     return "Helvetica-Oblique"
        case .HelveticaBoldOblique: return "Helvetica-BoldOblique"
        case .TimesRoman:           return "Times-Roman"
        case .TimesBold:            return "Times-Bold"
        case .TimesItalic:          return "Times-Italic"
        case .TimesBoldItalic:      return "Times-BoldItalic"
        case .Courier:              return "Courier"
        case .CourierBold:          return "Courier-Bold"
        case .CourierOblique:       return "Courier-Oblique"
        case .CourierBoldOblique:   return "Courier-BoldOblique"
        }
    }

    // Returns the face a `BaseFont` name selects, and whether the name was recognized.
    //
    // A subset prefix such as `ABCDEF+` is ignored, and both the `Arial` and `TimesNewRoman`
    // spellings map to the metrically compatible standard face.
    func fromBaseName(name: string)->{ font: StandardFont, found: bool }
    {
        var plain = name
        if @countof(plain) > 7 and plain[6] == '+' do
            plain = plain[7 until]
        if !@countof(plain) do
            return {StandardFont.Helvetica, false}

        var lower: String = plain
        lower.makeLower()
        let bold  = lower.contains("bold") or lower.contains("black") or lower.contains("heavy")
        let slant = lower.contains("italic") or lower.contains("oblique")

        if lower.contains("courier") or lower.contains("mono")
        {
            if bold and slant do
                return {StandardFont.CourierBoldOblique, true}
            if bold do
                return {StandardFont.CourierBold, true}
            if slant do
                return {StandardFont.CourierOblique, true}
            return {StandardFont.Courier, true}
        }

        if lower.contains("times") or lower.contains("serif") or lower.contains("roman") or lower.contains("georgia") or lower.contains("garamond")
        {
            if bold and slant do
                return {StandardFont.TimesBoldItalic, true}
            if bold do
                return {StandardFont.TimesBold, true}
            if slant do
                return {StandardFont.TimesItalic, true}
            return {StandardFont.TimesRoman, true}
        }

        if lower.contains("helvetica") or lower.contains("arial")
        {
            if bold and slant do
                return {StandardFont.HelveticaBoldOblique, true}
            if bold do
                return {StandardFont.HelveticaBold, true}
            if slant do
                return {StandardFont.HelveticaOblique, true}
            return {StandardFont.Helvetica, true}
        }

        return {StandardFont.Helvetica, false}
    }

    // Returns the advance width of one character, in fractions of the text size.
    //
    // The tables cover the printable ASCII range exactly. A Latin letter carrying an accent
    // has the advance of its base letter in these faces, which is exact as well; any other
    // character outside the tables is measured with a representative width.
    mtd const glyphWidth(value: rune)->f32
    {
        switch me
        {
        case .Courier, .CourierBold, .CourierOblique, .CourierBoldOblique: return cast(f32) CourierWidth / 1000.0
        }

        let table = standardWidths(me)
        var code  = cast(u32) value
        if code < StandardWidthFirst or code > StandardWidthLast
        {
            let base = latinBaseRune(value)
            if !base do
                return cast(f32) table[cast(u32) '0' - StandardWidthFirst] / 1000.0
            code = cast(u32) base
        }

        return cast(f32) table[code - StandardWidthFirst] / 1000.0
    }

    // Returns the advance width of `text` when drawn at `size` PDF points.
    //
    // Character spacing, word spacing, and horizontal scaling are not applied; this is the
    // natural width of the run.
    mtd const textWidth(text: string, size: f32)->f32
    {
        let font  = me
        var total = 0.0'f32
        Utf8.visitRunes(text)
        {
            total += font.glyphWidth(c)
        }

        return total * size
    }
}

private func standardWidths(font: StandardFont)->const [..] u16
{
    switch font
    {
    case .HelveticaBold, .HelveticaBoldOblique: return HelveticaBoldWidths
    case .TimesRoman:      return TimesRomanWidths
    case .TimesBold:       return TimesBoldWidths
    case .TimesItalic:     return TimesItalicWidths
    case .TimesBoldItalic: return TimesBoldItalicWidths
    }

    return HelveticaWidths
}

// Returns the unaccented Latin letter a character is composed from, or zero.
//
// The standard faces give a composed glyph the advance of its base letter, so this mapping
// makes the metric tables exact over the whole Latin-1 range without storing it.
private func latinBaseRune(value: rune)->rune
{
    switch value
    {
    case 0x00A0:         return ' '
    case 0x00AD, 0x2010: return '-'
    }

    switch
    {
    case value >= 0x00C0 and value <= 0x00C5: return 'A'
    case value == 0x00C7:                     return 'C'
    case value >= 0x00C8 and value <= 0x00CB: return 'E'
    case value >= 0x00CC and value <= 0x00CF: return 'I'
    case value == 0x00D1:                     return 'N'
    case value >= 0x00D2 and value <= 0x00D6: return 'O'
    case value >= 0x00D9 and value <= 0x00DC: return 'U'
    case value == 0x00DD:                     return 'Y'
    case value >= 0x00E0 and value <= 0x00E5: return 'a'
    case value == 0x00E7:                     return 'c'
    case value >= 0x00E8 and value <= 0x00EB: return 'e'
    case value >= 0x00EC and value <= 0x00EF: return 'i'
    case value == 0x00F1:                     return 'n'
    case value >= 0x00F2 and value <= 0x00F6: return 'o'
    case value >= 0x00F9 and value <= 0x00FC: return 'u'
    case value == 0x00FD or value == 0x00FF:  return 'y'
    case value == 0x0160 or value == 0x015A:  return 'S'
    case value == 0x0161 or value == 0x015B:  return 's'
    case value == 0x017D or value == 0x0179:  return 'Z'
    case value == 0x017E or value == 0x017A:  return 'z'
    case value == 0x0178:                     return 'Y'
    case value == 0x0141:                     return 'L'
    case value == 0x0142:                     return 'l'
    case value == 0x0131:                     return 'i'
    }

    return 0
}
