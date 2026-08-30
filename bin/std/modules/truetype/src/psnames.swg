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
    {161, 96}, {162, 97}, {163, 98}, {164, 99}, {165, 100}, {166, 101}, {167, 102}, {168, 103},
    {169, 104}, {170, 105}, {171, 106}, {172, 107}, {173, 108}, {174, 109}, {175, 110}, {177, 111},
    {178, 112}, {179, 113}, {180, 114}, {182, 115}, {183, 116}, {184, 117}, {185, 118}, {186, 119},
    {187, 120}, {188, 121}, {189, 122}, {191, 123}, {193, 124}, {194, 125}, {195, 126}, {196, 127},
    {197, 128}, {198, 129}, {199, 130}, {200, 131}, {202, 132}, {203, 133}, {205, 134}, {206, 135},
    {207, 136}, {208, 137}, {225, 138}, {227, 139}, {232, 140}, {233, 141}, {234, 142}, {235, 143},
    {241, 144}, {245, 145}, {248, 146}, {249, 147}, {250, 148}, {251, 149}]

// Characters StandardEncoding places where it departs from ASCII.
//
// A font program that ships no `cmap` is addressed through its built-in encoding, so this
// is what turns that encoding into the Unicode map the rest of the module expects.
private const StandardEncodingRunes: [56] { code: u8, value: u16 } = [
    {0x27, 0x2019}, {0x60, 0x2018}, {0xA1, 0x00A1}, {0xA2, 0x00A2}, {0xA3, 0x00A3}, {0xA4, 0x2044},
    {0xA5, 0x00A5}, {0xA6, 0x0192}, {0xA7, 0x00A7}, {0xA8, 0x00A4}, {0xA9, 0x0027}, {0xAA, 0x201C},
    {0xAB, 0x00AB}, {0xAC, 0x2039}, {0xAD, 0x203A}, {0xAE, 0xFB01}, {0xAF, 0xFB02}, {0xB1, 0x2013},
    {0xB2, 0x2020}, {0xB3, 0x2021}, {0xB4, 0x00B7}, {0xB6, 0x00B6}, {0xB7, 0x2022}, {0xB8, 0x201A},
    {0xB9, 0x201E}, {0xBA, 0x201D}, {0xBB, 0x00BB}, {0xBC, 0x2026}, {0xBD, 0x2030}, {0xBF, 0x00BF},
    {0xC1, 0x0060}, {0xC2, 0x00B4}, {0xC3, 0x02C6}, {0xC4, 0x02DC}, {0xC5, 0x00AF}, {0xC6, 0x02D8},
    {0xC7, 0x02D9}, {0xC8, 0x00A8}, {0xCA, 0x02DA}, {0xCB, 0x00B8}, {0xCD, 0x02DD}, {0xCE, 0x02DB},
    {0xCF, 0x02C7}, {0xD0, 0x2014}, {0xE1, 0x00C6}, {0xE3, 0x00AA}, {0xE8, 0x0141}, {0xE9, 0x00D8},
    {0xEA, 0x0152}, {0xEB, 0x00BA}, {0xF1, 0x00E6}, {0xF5, 0x0131}, {0xF8, 0x0142}, {0xF9, 0x00F8},
    {0xFA, 0x0153}, {0xFB, 0x00DF}]

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
        return StandardStrings[cast(u32) code - 31]
    for entry in StandardEncodingHigh where entry.code == code do
        return StandardStrings[entry.sid]
    return ""
}

// Returns the character StandardEncoding places at `code`, or zero for an unused slot.
func standardEncodingRune(code: u8)->rune
{
    for entry in StandardEncodingRunes where entry.code == code do
        return cast(rune) entry.value
    if code >= 0x20 and code < 0x7F do
        return cast(rune) code
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
    for c in cast(const [..] u8) digits
    {
        var value = 0'u32
        if c >= '0' and c <= '9' do
            value = c - '0'
        elif c >= 'A' and c <= 'F' do
            value = cast(u32) (c - 'A') + 10
        elif c >= 'a' and c <= 'f' do
            value = cast(u32) (c - 'a') + 10
        else do
            return 0
        result = result * 16 + value
    }

    return cast(rune) result
}
