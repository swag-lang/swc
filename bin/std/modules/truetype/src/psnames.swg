using Swag, Core

// The 391 names every CFF font may refer to by index instead of spelling out.
//
// A CFF charset stores a string identifier per glyph; identifiers below this table's
// length name one of these, and the rest index the font's own string INDEX. Type 1
// fonts spell their names out, but share the vocabulary.
const StandardStrings: [391] string = [
    ".notdef", "space", "exclam", "quotedbl", "numbersign", "dollar", "percent", "ampersand",
    "quoteright", "parenleft", "parenright", "asterisk", "plus", "comma", "hyphen", "period",
    "slash", "zero", "one", "two", "three", "four", "five", "six",
    "seven", "eight", "nine", "colon", "semicolon", "less", "equal", "greater",
    "question", "at", "A", "B", "C", "D", "E", "F",
    "G", "H", "I", "J", "K", "L", "M", "N",
    "O", "P", "Q", "R", "S", "T", "U", "V",
    "W", "X", "Y", "Z", "bracketleft", "backslash", "bracketright", "asciicircum",
    "underscore", "quoteleft", "a", "b", "c", "d", "e", "f",
    "g", "h", "i", "j", "k", "l", "m", "n",
    "o", "p", "q", "r", "s", "t", "u", "v",
    "w", "x", "y", "z", "braceleft", "bar", "braceright", "asciitilde",
    "exclamdown", "cent", "sterling", "fraction", "yen", "florin", "section", "currency",
    "quotesingle", "quotedblleft", "guillemotleft", "guilsinglleft", "guilsinglright", "fi", "fl", "endash",
    "dagger", "daggerdbl", "periodcentered", "paragraph", "bullet", "quotesinglbase", "quotedblbase", "quotedblright",
    "guillemotright", "ellipsis", "perthousand", "questiondown", "grave", "acute", "circumflex", "tilde",
    "macron", "breve", "dotaccent", "dieresis", "ring", "cedilla", "hungarumlaut", "ogonek",
    "caron", "emdash", "AE", "ordfeminine", "Lslash", "Oslash", "OE", "ordmasculine",
    "ae", "dotlessi", "lslash", "oslash", "oe", "germandbls", "onesuperior", "logicalnot",
    "mu", "trademark", "Eth", "onehalf", "plusminus", "Thorn", "onequarter", "divide",
    "brokenbar", "degree", "thorn", "threequarters", "twosuperior", "registered", "minus", "eth",
    "multiply", "threesuperior", "copyright", "Aacute", "Acircumflex", "Adieresis", "Agrave", "Aring",
    "Atilde", "Ccedilla", "Eacute", "Ecircumflex", "Edieresis", "Egrave", "Iacute", "Icircumflex",
    "Idieresis", "Igrave", "Ntilde", "Oacute", "Ocircumflex", "Odieresis", "Ograve", "Otilde",
    "Scaron", "Uacute", "Ucircumflex", "Udieresis", "Ugrave", "Yacute", "Ydieresis", "Zcaron",
    "aacute", "acircumflex", "adieresis", "agrave", "aring", "atilde", "ccedilla", "eacute",
    "ecircumflex", "edieresis", "egrave", "iacute", "icircumflex", "idieresis", "igrave", "ntilde",
    "oacute", "ocircumflex", "odieresis", "ograve", "otilde", "scaron", "uacute", "ucircumflex",
    "udieresis", "ugrave", "yacute", "ydieresis", "zcaron", "exclamsmall", "Hungarumlautsmall", "dollaroldstyle",
    "dollarsuperior", "ampersandsmall", "Acutesmall", "parenleftsuperior", "parenrightsuperior", "twodotenleader", "onedotenleader", "zerooldstyle",
    "oneoldstyle", "twooldstyle", "threeoldstyle", "fouroldstyle", "fiveoldstyle", "sixoldstyle", "sevenoldstyle", "eightoldstyle",
    "nineoldstyle", "commasuperior", "threequartersemdash", "periodsuperior", "questionsmall", "asuperior", "bsuperior", "centsuperior",
    "dsuperior", "esuperior", "isuperior", "lsuperior", "msuperior", "nsuperior", "osuperior", "rsuperior",
    "ssuperior", "tsuperior", "ff", "ffi", "ffl", "parenleftinferior", "parenrightinferior", "Circumflexsmall",
    "hyphensuperior", "Gravesmall", "Asmall", "Bsmall", "Csmall", "Dsmall", "Esmall", "Fsmall",
    "Gsmall", "Hsmall", "Ismall", "Jsmall", "Ksmall", "Lsmall", "Msmall", "Nsmall",
    "Osmall", "Psmall", "Qsmall", "Rsmall", "Ssmall", "Tsmall", "Usmall", "Vsmall",
    "Wsmall", "Xsmall", "Ysmall", "Zsmall", "colonmonetary", "onefitted", "rupiah", "Tildesmall",
    "exclamdownsmall", "centoldstyle", "Lslashsmall", "Scaronsmall", "Zcaronsmall", "Dieresissmall", "Brevesmall", "Caronsmall",
    "Dotaccentsmall", "Macronsmall", "figuredash", "hypheninferior", "Ogoneksmall", "Ringsmall", "Cedillasmall", "questiondownsmall",
    "oneeighth", "threeeighths", "fiveeighths", "seveneighths", "onethird", "twothirds", "zerosuperior", "foursuperior",
    "fivesuperior", "sixsuperior", "sevensuperior", "eightsuperior", "ninesuperior", "zeroinferior", "oneinferior", "twoinferior",
    "threeinferior", "fourinferior", "fiveinferior", "sixinferior", "seveninferior", "eightinferior", "nineinferior", "centinferior",
    "dollarinferior", "periodinferior", "commainferior", "Agravesmall", "Aacutesmall", "Acircumflexsmall", "Atildesmall", "Adieresissmall",
    "Aringsmall", "AEsmall", "Ccedillasmall", "Egravesmall", "Eacutesmall", "Ecircumflexsmall", "Edieresissmall", "Igravesmall",
    "Iacutesmall", "Icircumflexsmall", "Idieresissmall", "Ethsmall", "Ntildesmall", "Ogravesmall", "Oacutesmall", "Ocircumflexsmall",
    "Otildesmall", "Odieresissmall", "OEsmall", "Oslashsmall", "Ugravesmall", "Uacutesmall", "Ucircumflexsmall", "Udieresissmall",
    "Yacutesmall", "Thornsmall", "Ydieresissmall", "001.000", "001.001", "001.002", "001.003", "Black",
    "Bold", "Book", "Light", "Medium", "Regular", "Roman", "Semibold"]

// Codes StandardEncoding fills above the contiguous run, paired with their name index.
//
// Codes 32 through 126 name the first ninety-five standard strings in order, which is
// why only the sparse tail needs spelling out.
private const StandardEncodingHigh: [54] { code: u8, sid: u16 } = [
    {code: 161, sid: 96}, {code: 162, sid: 97}, {code: 163, sid: 98}, {code: 164, sid: 99}, {code: 165, sid: 100}, {code: 166, sid: 101}, {code: 167, sid: 102}, {code: 168, sid: 103},
    {code: 169, sid: 104}, {code: 170, sid: 105}, {code: 171, sid: 106}, {code: 172, sid: 107}, {code: 173, sid: 108}, {code: 174, sid: 109}, {code: 175, sid: 110}, {code: 177, sid: 111},
    {code: 178, sid: 112}, {code: 179, sid: 113}, {code: 180, sid: 114}, {code: 182, sid: 115}, {code: 183, sid: 116}, {code: 184, sid: 117}, {code: 185, sid: 118}, {code: 186, sid: 119},
    {code: 187, sid: 120}, {code: 188, sid: 121}, {code: 189, sid: 122}, {code: 191, sid: 123}, {code: 193, sid: 124}, {code: 194, sid: 125}, {code: 195, sid: 126}, {code: 196, sid: 127},
    {code: 197, sid: 128}, {code: 198, sid: 129}, {code: 199, sid: 130}, {code: 200, sid: 131}, {code: 202, sid: 132}, {code: 203, sid: 133}, {code: 205, sid: 134}, {code: 206, sid: 135},
    {code: 207, sid: 136}, {code: 208, sid: 137}, {code: 225, sid: 138}, {code: 227, sid: 139}, {code: 232, sid: 140}, {code: 233, sid: 141}, {code: 234, sid: 142}, {code: 235, sid: 143},
    {code: 241, sid: 144}, {code: 245, sid: 145}, {code: 248, sid: 146}, {code: 249, sid: 147}, {code: 250, sid: 148}, {code: 251, sid: 149}]

// Characters StandardEncoding places where it departs from ASCII.
//
// A font program that ships no `cmap` is addressed through its built-in encoding, so this
// is what turns that encoding into the Unicode map the rest of the module expects.
private const StandardEncodingRunes: [56] { code: u8, value: u16 } = [
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

// Returns the standard string a name identifier selects, or an empty name for one that
// belongs to the font's own string INDEX.
func standardString(sid: u32)->string
{
    if sid < StandardStrings.count do
        return StandardStrings[sid]
    return ""
}

// Returns the name StandardEncoding gives to one code, or an empty name for an unused slot.
func standardEncodingName(code: u8)->string
{
    if code >= 32 and code <= 126 do
        return StandardStrings[cast(u32, code) - 31]
    for entry in StandardEncodingHigh where entry.code == code do
        return StandardStrings[entry.sid]
    return ""
}

// Returns the character StandardEncoding places at `code`, or zero for an unused slot.
func standardEncodingRune(code: u8)->rune
{
    for entry in StandardEncodingRunes where entry.code == code do
        return cast(rune, entry.value)
    if code >= 0x20 and code < 0x7F do
        return cast(rune, code)
    return 0
}

// Returns the character a glyph name stands for, or zero when the name is unknown.
//
// Only the `uniXXXX` and `uXXXX` conventions are decoded here; a name that belongs to the
// standard vocabulary is resolved through [[standardEncodingRune]] by way of the code that
// selects it, which is the path a font with no character map is addressed by.
func glyphNameRune(name: string)->rune
{
    if name.count == 7 and name[0 to 2] == "uni" do
        return parseNameHex(name[3 until])
    if name.count >= 5 and name.count <= 7 and name[0] == 'u' do
        return parseNameHex(name[1 until])
    return 0
}

private func parseNameHex(digits: string)->rune
{
    var result = 0'u32
    for c in cast(const [..] u8, digits)
    {
        var value = 0'u32
        if c >= '0' and c <= '9' do
            value = c - '0'
        elif c >= 'A' and c <= 'F' do
            value = cast(u32, (c - 'A')) + 10
        elif c >= 'a' and c <= 'f' do
            value = cast(u32, (c - 'a')) + 10
        else do
            return 0
        result = result * 16 + value
    }

    return cast(rune, result)
}
