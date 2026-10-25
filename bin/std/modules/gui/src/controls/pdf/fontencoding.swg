#global namespace Pdf

using Core

// The single-byte encodings a simple font can name, and the glyph names a `/Differences`
// array can use to override one code.
//
// Every table is embedded here: mapping a byte to a character never consults a system
// font, a code page service, or any other outside source.
enum BaseEncoding
{
    Standard
    WinAnsi
    MacRoman
}

// Codes of StandardEncoding that differ from ASCII, paired with the character they name.
private const StandardEncodingHigh: [56] { code: u8, value: u16 } = [
    {code: 0x27, value: 0x2019}, {code: 0x60, value: 0x2018}, {code: 0xA1, value: 0x00A1}, {code: 0xA2, value: 0x00A2}, {code: 0xA3, value: 0x00A3}, {code: 0xA4, value: 0x2044},
    {code: 0xA5, value: 0x00A5}, {code: 0xA6, value: 0x0192}, {code: 0xA7, value: 0x00A7}, {code: 0xA8, value: 0x00A4}, {code: 0xA9, value: 0x0027}, {code: 0xAA, value: 0x201C},
    {code: 0xAB, value: 0x00AB}, {code: 0xAC, value: 0x2039}, {code: 0xAD, value: 0x203A}, {code: 0xAE, value: 0xFB01}, {code: 0xAF, value: 0xFB02}, {code: 0xB1, value: 0x2013},
    {code: 0xB2, value: 0x2020}, {code: 0xB3, value: 0x2021}, {code: 0xB4, value: 0x00B7}, {code: 0xB6, value: 0x00B6}, {code: 0xB7, value: 0x2022}, {code: 0xB8, value: 0x201A},
    {code: 0xB9, value: 0x201E}, {code: 0xBA, value: 0x201D}, {code: 0xBB, value: 0x00BB}, {code: 0xBC, value: 0x2026}, {code: 0xBD, value: 0x2030}, {code: 0xBF, value: 0x00BF},
    {code: 0xC1, value: 0x0060}, {code: 0xC2, value: 0x00B4}, {code: 0xC3, value: 0x02C6}, {code: 0xC4, value: 0x02DC}, {code: 0xC5, value: 0x00AF}, {code: 0xC6, value: 0x02D8},
    {code: 0xC7, value: 0x02D9}, {code: 0xC8, value: 0x00A8}, {code: 0xCA, value: 0x02DA}, {code: 0xCB, value: 0x00B8}, {code: 0xCD, value: 0x02DD}, {code: 0xCE, value: 0x02DB},
    {code: 0xCF, value: 0x02C7}, {code: 0xD0, value: 0x2014}, {code: 0xE1, value: 0x00C6}, {code: 0xE3, value: 0x00AA}, {code: 0xE8, value: 0x0141}, {code: 0xE9, value: 0x00D8},
    {code: 0xEA, value: 0x0152}, {code: 0xEB, value: 0x00BA}, {code: 0xF1, value: 0x00E6}, {code: 0xF5, value: 0x0131}, {code: 0xF8, value: 0x0142}, {code: 0xF9, value: 0x00F8},
    {code: 0xFA, value: 0x0153}, {code: 0xFB, value: 0x00DF}]

// Characters MacRomanEncoding places at codes 0x80 through 0xFF.
private const MacRomanEncodingHigh: [128] u16 = [
    0x00C4, 0x00C5, 0x00C7, 0x00C9, 0x00D1, 0x00D6, 0x00DC, 0x00E1, 0x00E0, 0x00E2, 0x00E4, 0x00E3, 0x00E5, 0x00E7, 0x00E9, 0x00E8,
    0x00EA, 0x00EB, 0x00ED, 0x00EC, 0x00EE, 0x00EF, 0x00F1, 0x00F3, 0x00F2, 0x00F4, 0x00F6, 0x00F5, 0x00FA, 0x00F9, 0x00FB, 0x00FC,
    0x2020, 0x00B0, 0x00A2, 0x00A3, 0x00A7, 0x2022, 0x00B6, 0x00DF, 0x00AE, 0x00A9, 0x2122, 0x00B4, 0x00A8, 0x2260, 0x00C6, 0x00D8,
    0x221E, 0x00B1, 0x2264, 0x2265, 0x00A5, 0x00B5, 0x2202, 0x2211, 0x220F, 0x03C0, 0x222B, 0x00AA, 0x00BA, 0x03A9, 0x00E6, 0x00F8,
    0x00BF, 0x00A1, 0x00AC, 0x221A, 0x0192, 0x2248, 0x2206, 0x00AB, 0x00BB, 0x2026, 0x00A0, 0x00C0, 0x00C3, 0x00D5, 0x0152, 0x0153,
    0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0x00F7, 0x25CA, 0x00FF, 0x0178, 0x2044, 0x00A4, 0x2039, 0x203A, 0xFB01, 0xFB02,
    0x2021, 0x00B7, 0x201A, 0x201E, 0x2030, 0x00C2, 0x00CA, 0x00C1, 0x00CB, 0x00C8, 0x00CD, 0x00CE, 0x00CF, 0x00CC, 0x00D3, 0x00D4,
    0xF8FF, 0x00D2, 0x00DA, 0x00DB, 0x00D9, 0x0131, 0x02C6, 0x02DC, 0x00AF, 0x02D8, 0x02D9, 0x02DA, 0x00B8, 0x02DD, 0x02DB, 0x02C7]

// Every glyph name the four standard encodings use, with the character it stands for.
//
// A `/Differences` array names glyphs instead of characters, so text extraction needs this
// table to turn an overridden code back into text.
private const GlyphNames: [243] { name: string, value: u16 } = [
    {name: "space", value: 0x0020}, {name: "exclam", value: 0x0021}, {name: "quotedbl", value: 0x0022}, {name: "numbersign", value: 0x0023},
    {name: "dollar", value: 0x0024}, {name: "percent", value: 0x0025}, {name: "ampersand", value: 0x0026}, {name: "quotesingle", value: 0x0027},
    {name: "parenleft", value: 0x0028}, {name: "parenright", value: 0x0029}, {name: "asterisk", value: 0x002A}, {name: "plus", value: 0x002B},
    {name: "comma", value: 0x002C}, {name: "hyphen", value: 0x002D}, {name: "period", value: 0x002E}, {name: "slash", value: 0x002F},
    {name: "zero", value: 0x0030}, {name: "one", value: 0x0031}, {name: "two", value: 0x0032}, {name: "three", value: 0x0033},
    {name: "four", value: 0x0034}, {name: "five", value: 0x0035}, {name: "six", value: 0x0036}, {name: "seven", value: 0x0037},
    {name: "eight", value: 0x0038}, {name: "nine", value: 0x0039}, {name: "colon", value: 0x003A}, {name: "semicolon", value: 0x003B},
    {name: "less", value: 0x003C}, {name: "equal", value: 0x003D}, {name: "greater", value: 0x003E}, {name: "question", value: 0x003F},
    {name: "at", value: 0x0040}, {name: "A", value: 0x0041}, {name: "B", value: 0x0042}, {name: "C", value: 0x0043},
    {name: "D", value: 0x0044}, {name: "E", value: 0x0045}, {name: "F", value: 0x0046}, {name: "G", value: 0x0047},
    {name: "H", value: 0x0048}, {name: "I", value: 0x0049}, {name: "J", value: 0x004A}, {name: "K", value: 0x004B},
    {name: "L", value: 0x004C}, {name: "M", value: 0x004D}, {name: "N", value: 0x004E}, {name: "O", value: 0x004F},
    {name: "P", value: 0x0050}, {name: "Q", value: 0x0051}, {name: "R", value: 0x0052}, {name: "S", value: 0x0053},
    {name: "T", value: 0x0054}, {name: "U", value: 0x0055}, {name: "V", value: 0x0056}, {name: "W", value: 0x0057},
    {name: "X", value: 0x0058}, {name: "Y", value: 0x0059}, {name: "Z", value: 0x005A}, {name: "bracketleft", value: 0x005B},
    {name: "backslash", value: 0x005C}, {name: "bracketright", value: 0x005D}, {name: "asciicircum", value: 0x005E}, {name: "underscore", value: 0x005F},
    {name: "grave", value: 0x0060}, {name: "a", value: 0x0061}, {name: "b", value: 0x0062}, {name: "c", value: 0x0063},
    {name: "d", value: 0x0064}, {name: "e", value: 0x0065}, {name: "f", value: 0x0066}, {name: "g", value: 0x0067},
    {name: "h", value: 0x0068}, {name: "i", value: 0x0069}, {name: "j", value: 0x006A}, {name: "k", value: 0x006B},
    {name: "l", value: 0x006C}, {name: "m", value: 0x006D}, {name: "n", value: 0x006E}, {name: "o", value: 0x006F},
    {name: "p", value: 0x0070}, {name: "q", value: 0x0071}, {name: "r", value: 0x0072}, {name: "s", value: 0x0073},
    {name: "t", value: 0x0074}, {name: "u", value: 0x0075}, {name: "v", value: 0x0076}, {name: "w", value: 0x0077},
    {name: "x", value: 0x0078}, {name: "y", value: 0x0079}, {name: "z", value: 0x007A}, {name: "braceleft", value: 0x007B},
    {name: "bar", value: 0x007C}, {name: "braceright", value: 0x007D}, {name: "asciitilde", value: 0x007E}, {name: "exclamdown", value: 0x00A1},
    {name: "cent", value: 0x00A2}, {name: "sterling", value: 0x00A3}, {name: "currency", value: 0x00A4}, {name: "yen", value: 0x00A5},
    {name: "brokenbar", value: 0x00A6}, {name: "section", value: 0x00A7}, {name: "dieresis", value: 0x00A8}, {name: "copyright", value: 0x00A9},
    {name: "ordfeminine", value: 0x00AA}, {name: "guillemotleft", value: 0x00AB}, {name: "logicalnot", value: 0x00AC}, {name: "registered", value: 0x00AE},
    {name: "macron", value: 0x00AF}, {name: "degree", value: 0x00B0}, {name: "plusminus", value: 0x00B1}, {name: "twosuperior", value: 0x00B2},
    {name: "threesuperior", value: 0x00B3}, {name: "acute", value: 0x00B4}, {name: "mu", value: 0x00B5}, {name: "paragraph", value: 0x00B6},
    {name: "periodcentered", value: 0x00B7}, {name: "cedilla", value: 0x00B8}, {name: "onesuperior", value: 0x00B9}, {name: "ordmasculine", value: 0x00BA},
    {name: "guillemotright", value: 0x00BB}, {name: "onequarter", value: 0x00BC}, {name: "onehalf", value: 0x00BD}, {name: "threequarters", value: 0x00BE},
    {name: "questiondown", value: 0x00BF}, {name: "Agrave", value: 0x00C0}, {name: "Aacute", value: 0x00C1}, {name: "Acircumflex", value: 0x00C2},
    {name: "Atilde", value: 0x00C3}, {name: "Adieresis", value: 0x00C4}, {name: "Aring", value: 0x00C5}, {name: "AE", value: 0x00C6},
    {name: "Ccedilla", value: 0x00C7}, {name: "Egrave", value: 0x00C8}, {name: "Eacute", value: 0x00C9}, {name: "Ecircumflex", value: 0x00CA},
    {name: "Edieresis", value: 0x00CB}, {name: "Igrave", value: 0x00CC}, {name: "Iacute", value: 0x00CD}, {name: "Icircumflex", value: 0x00CE},
    {name: "Idieresis", value: 0x00CF}, {name: "Eth", value: 0x00D0}, {name: "Ntilde", value: 0x00D1}, {name: "Ograve", value: 0x00D2},
    {name: "Oacute", value: 0x00D3}, {name: "Ocircumflex", value: 0x00D4}, {name: "Otilde", value: 0x00D5}, {name: "Odieresis", value: 0x00D6},
    {name: "multiply", value: 0x00D7}, {name: "Oslash", value: 0x00D8}, {name: "Ugrave", value: 0x00D9}, {name: "Uacute", value: 0x00DA},
    {name: "Ucircumflex", value: 0x00DB}, {name: "Udieresis", value: 0x00DC}, {name: "Yacute", value: 0x00DD}, {name: "Thorn", value: 0x00DE},
    {name: "germandbls", value: 0x00DF}, {name: "agrave", value: 0x00E0}, {name: "aacute", value: 0x00E1}, {name: "acircumflex", value: 0x00E2},
    {name: "atilde", value: 0x00E3}, {name: "adieresis", value: 0x00E4}, {name: "aring", value: 0x00E5}, {name: "ae", value: 0x00E6},
    {name: "ccedilla", value: 0x00E7}, {name: "egrave", value: 0x00E8}, {name: "eacute", value: 0x00E9}, {name: "ecircumflex", value: 0x00EA},
    {name: "edieresis", value: 0x00EB}, {name: "igrave", value: 0x00EC}, {name: "iacute", value: 0x00ED}, {name: "icircumflex", value: 0x00EE},
    {name: "idieresis", value: 0x00EF}, {name: "eth", value: 0x00F0}, {name: "ntilde", value: 0x00F1}, {name: "ograve", value: 0x00F2},
    {name: "oacute", value: 0x00F3}, {name: "ocircumflex", value: 0x00F4}, {name: "otilde", value: 0x00F5}, {name: "odieresis", value: 0x00F6},
    {name: "divide", value: 0x00F7}, {name: "oslash", value: 0x00F8}, {name: "ugrave", value: 0x00F9}, {name: "uacute", value: 0x00FA},
    {name: "ucircumflex", value: 0x00FB}, {name: "udieresis", value: 0x00FC}, {name: "yacute", value: 0x00FD}, {name: "thorn", value: 0x00FE},
    {name: "ydieresis", value: 0x00FF}, {name: "dotlessi", value: 0x0131}, {name: "Lslash", value: 0x0141}, {name: "lslash", value: 0x0142},
    {name: "OE", value: 0x0152}, {name: "oe", value: 0x0153}, {name: "Scaron", value: 0x0160}, {name: "scaron", value: 0x0161},
    {name: "Ydieresis", value: 0x0178}, {name: "Zcaron", value: 0x017D}, {name: "zcaron", value: 0x017E}, {name: "florin", value: 0x0192},
    {name: "circumflex", value: 0x02C6}, {name: "caron", value: 0x02C7}, {name: "breve", value: 0x02D8}, {name: "dotaccent", value: 0x02D9},
    {name: "ring", value: 0x02DA}, {name: "ogonek", value: 0x02DB}, {name: "tilde", value: 0x02DC}, {name: "hungarumlaut", value: 0x02DD},
    {name: "pi", value: 0x03C0}, {name: "Omega", value: 0x03A9}, {name: "endash", value: 0x2013}, {name: "emdash", value: 0x2014},
    {name: "quoteleft", value: 0x2018}, {name: "quoteright", value: 0x2019}, {name: "quotesinglbase", value: 0x201A}, {name: "quotedblleft", value: 0x201C},
    {name: "quotedblright", value: 0x201D}, {name: "quotedblbase", value: 0x201E}, {name: "dagger", value: 0x2020}, {name: "daggerdbl", value: 0x2021},
    {name: "bullet", value: 0x2022}, {name: "ellipsis", value: 0x2026}, {name: "perthousand", value: 0x2030}, {name: "guilsinglleft", value: 0x2039},
    {name: "guilsinglright", value: 0x203A}, {name: "fraction", value: 0x2044}, {name: "Euro", value: 0x20AC}, {name: "trademark", value: 0x2122},
    {name: "partialdiff", value: 0x2202}, {name: "Delta", value: 0x2206}, {name: "product", value: 0x220F}, {name: "summation", value: 0x2211},
    {name: "radical", value: 0x221A}, {name: "infinity", value: 0x221E}, {name: "integral", value: 0x222B}, {name: "approxequal", value: 0x2248},
    {name: "notequal", value: 0x2260}, {name: "lessequal", value: 0x2264}, {name: "greaterequal", value: 0x2265}, {name: "lozenge", value: 0x25CA},
    {name: "fi", value: 0xFB01}, {name: "fl", value: 0xFB02}, {name: "apple", value: 0xF8FF}]

// Returns the character an encoding places at `code`, or zero when the slot is unused.
func encodingRune(encoding: BaseEncoding, code: u8)->rune
{
    switch #complete encoding
    {
    case .WinAnsi:
        return Text.windows1252Rune(code)

    case .MacRoman:
        if code < 0x80 do
            return cast(rune, code)
        return cast(rune, MacRomanEncodingHigh[code - 0x80])

    case .Standard:
        for entry in StandardEncodingHigh where entry.code == code do
            return cast(rune, entry.value)
        if code >= 0x20 and code < 0x7F do
            return cast(rune, code)
        return 0
    }
}

// Returns the character a glyph name stands for, or zero when the name is unknown.
//
// The `uniXXXX` and `uXXXX` forms are recognized in addition to the table, so a font that
// names glyphs by code point still extracts as text.
func glyphNameRune(name: string)->rune
{
    for entry in GlyphNames where entry.name == name do
        return cast(rune, entry.value)

    if name.count == 7 and name[0 to 2] == "uni" do
        return parseGlyphHex(name[3 until])
    if name.count >= 5 and name.count <= 7 and name[0] == 'u' do
        return parseGlyphHex(name[1 until])
    return 0
}

// Returns the standard glyph name a character is written with, or an empty name when the
// character has none.
//
// This is what turns a code the encoding describes as a character back into the name an
// embedded PostScript program keys its outlines by.
func runeGlyphName(value: rune)->string
{
    for entry in GlyphNames where entry.value == cast(u32, value) do
        return entry.name
    return ""
}

private func parseGlyphHex(digits: string)->rune
{
    var result = 0'u32
    for c in cast(const [..] u8, digits)
    {
        if not isHex(c) do
            return 0
        result = result * 16 + hexValue(c)
    }

    return cast(rune, result)
}
