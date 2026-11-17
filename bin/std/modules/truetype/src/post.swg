using Swag, Core

// Macintosh standard glyph order used by the TrueType `post` table. This is the
// 258-name sequence defined for `post` formats 1, 2, and 2.5; it is not the CFF
// StandardStrings SID order.
private const MacStandardGlyphNames: [258] string = [
    ".notdef", ".null", "nonmarkingreturn", "space", "exclam", "quotedbl", "numbersign", "dollar",
    "percent", "ampersand", "quotesingle", "parenleft", "parenright", "asterisk", "plus", "comma",
    "hyphen", "period", "slash", "zero", "one", "two", "three", "four",
    "five", "six", "seven", "eight", "nine", "colon", "semicolon", "less",
    "equal", "greater", "question", "at", "A", "B", "C", "D",
    "E", "F", "G", "H", "I", "J", "K", "L",
    "M", "N", "O", "P", "Q", "R", "S", "T",
    "U", "V", "W", "X", "Y", "Z", "bracketleft", "backslash",
    "bracketright", "asciicircum", "underscore", "grave", "a", "b", "c", "d",
    "e", "f", "g", "h", "i", "j", "k", "l",
    "m", "n", "o", "p", "q", "r", "s", "t",
    "u", "v", "w", "x", "y", "z", "braceleft", "bar",
    "braceright", "asciitilde", "Adieresis", "Aring", "Ccedilla", "Eacute", "Ntilde", "Odieresis",
    "Udieresis", "aacute", "agrave", "acircumflex", "adieresis", "atilde", "aring", "ccedilla",
    "eacute", "egrave", "ecircumflex", "edieresis", "iacute", "igrave", "icircumflex", "idieresis",
    "ntilde", "oacute", "ograve", "ocircumflex", "odieresis", "otilde", "uacute", "ugrave",
    "ucircumflex", "udieresis", "dagger", "degree", "cent", "sterling", "section", "bullet",
    "paragraph", "germandbls", "registered", "copyright", "trademark", "acute", "dieresis", "notequal",
    "AE", "Oslash", "infinity", "plusminus", "lessequal", "greaterequal", "yen", "mu",
    "partialdiff", "summation", "product", "pi", "integral", "ordfeminine", "ordmasculine", "Omega",
    "ae", "oslash", "questiondown", "exclamdown", "logicalnot", "radical", "florin", "approxequal",
    "Delta", "guillemotleft", "guillemotright", "ellipsis", "nonbreakingspace", "Agrave", "Atilde", "Otilde",
    "OE", "oe", "endash", "emdash", "quotedblleft", "quotedblright", "quoteleft", "quoteright",
    "divide", "lozenge", "ydieresis", "Ydieresis", "fraction", "currency", "guilsinglleft", "guilsinglright",
    "fi", "fl", "daggerdbl", "periodcentered", "quotesinglbase", "quotedblbase", "perthousand", "Acircumflex",
    "Ecircumflex", "Aacute", "Edieresis", "Egrave", "Iacute", "Icircumflex", "Idieresis", "Igrave",
    "Oacute", "Ocircumflex", "apple", "Ograve", "Uacute", "Ucircumflex", "Ugrave", "dotlessi",
    "circumflex", "tilde", "macron", "breve", "dotaccent", "ring", "cedilla", "hungarumlaut",
    "ogonek", "caron", "Lslash", "lslash", "Scaron", "scaron", "Zcaron", "zcaron",
    "brokenbar", "Eth", "eth", "Yacute", "yacute", "Thorn", "thorn", "minus",
    "multiply", "onesuperior", "twosuperior", "threesuperior", "onehalf", "onequarter", "threequarters", "franc",
    "Gbreve", "gbreve", "Idotaccent", "Scedilla", "scedilla", "Cacute", "cacute", "Ccaron",
    "ccaron", "dcroat"]

// Adds a name once, matching the first-name-wins behavior of CFF and Type 1 maps.
private func addPostGlyphName(faceData: *FaceImpl, name: string, glyphIndex: u32)
{
    if name.count == 0 do
        return
    faceData.postGlyphNames[glyphIndex] = String.from(name)
    let key = String.from(name)
    if not faceData.postNameToGid.contains(key) do
        faceData.postNameToGid.add(key, glyphIndex)
}

func parsePostGlyphNames(faceData: *FaceImpl, postTable: const [..] u8, format: u32) fail
{
    let glyphCount = faceData.face.glyphCount
    if format == 0x00010000
    {
        if glyphCount > MacStandardGlyphNames.count do
            try fault(0x9B)
        faceData.postGlyphNames.resize(glyphCount)
        for glyphIndex in glyphCount do
            addPostGlyphName(faceData, MacStandardGlyphNames[glyphIndex], glyphIndex)
        return
    }

    if format == 0x00020000
    {
        let count = try readU16(postTable, 32)
        if count != glyphCount do
            try fault(0x9B)
        try assertRange(postTable, 34, cast(u64, count) * 2)
        faceData.postGlyphNames.resize(glyphCount)

        var indices: Array'u16
        indices.resize(count)
        var maxCustomIndex = 257'u16
        for glyphIndex in count
        {
            let nameIndex = try readU16(postTable, 34 + cast(u64, glyphIndex) * 2)
            indices[glyphIndex] = nameIndex
            if nameIndex >= 258 and nameIndex > maxCustomIndex do
                maxCustomIndex = nameIndex
        }

        var customNames: Array'String
        let customCount  = cast(u64, maxCustomIndex) - 257
        let customOffset = 34 + cast(u64, count) * 2
        if customCount > postTable.count - customOffset do
            try fault(0x9B)
        if maxCustomIndex >= 258
        {
            customNames.resize(customCount)
            var offset = customOffset
            for customIndex in 258'u32 until cast(u32, maxCustomIndex) + 1
            {
                let length = try readU8(postTable, offset)
                offset += 1
                let rawName = try getSlice(postTable, offset, length)
                offset += length
                customNames[customIndex - 258] = String.from(cast(string?, rawName))
            }
        }

        for glyphIndex in count
        {
            let nameIndex = indices[glyphIndex]
            let name      = nameIndex < 258 ? MacStandardGlyphNames[nameIndex] : customNames[nameIndex - 258].toString()
            addPostGlyphName(faceData, name, glyphIndex)
        }

        return
    }

    if format == 0x00025000
    {
        let count = try readU16(postTable, 32)
        if count != glyphCount do
            try fault(0x9B)
        try assertRange(postTable, 34, count)
        faceData.postGlyphNames.resize(glyphCount)
        for glyphIndex in glyphCount
        {
            let offset    = cast(s8, try readU8(postTable, 34 + glyphIndex))
            let nameIndex = cast(s32, glyphIndex) + cast(s32, offset)
            if nameIndex < 0 or nameIndex >= MacStandardGlyphNames.count do
                try fault(0x9B)
            addPostGlyphName(faceData, MacStandardGlyphNames[cast(u32, nameIndex)], glyphIndex)
        }
    }
}
