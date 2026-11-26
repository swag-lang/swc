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

func packedPostGlyphName(names: const *GlyphNames, indices: const [..] u8, glyphIndex: u32)->string?
{
    let entry     = indices.buffer + cast(u64, glyphIndex) * 2
    let nameIndex = Math.make16(entry[0], entry[1])
    if nameIndex < MacStandardGlyphNames.count do
        return MacStandardGlyphNames[nameIndex]

    let offset = names.postOffsets[nameIndex - MacStandardGlyphNames.count]
    let length = names.postStrings.buffer[offset]
    if not length do
        return null
    return cast(string?, Swag.makeSlice(names.postStrings.buffer + offset + 1, length))
}

func parsePostGlyphNames(faceData: *FaceImpl, postTable: const [..] u8, format: u32) fail
{
    let glyphCount = faceData.face.glyphCount
    if format == 0x00010000
    {
        if glyphCount > MacStandardGlyphNames.count do
            try fault(0x9B)
        faceData.postNames.entries.add(Swag.makeSlice(&MacStandardGlyphNames[0], glyphCount))
        return
    }

    if format == 0x00020000
    {
        let count = try readU16(postTable, 32)
        if count != glyphCount do
            try fault(0x9B)
        let indices = try getSlice(postTable, 34, cast(u64, count) * 2)
        if not count do
            return

        var maxCustomIndex = 257'u16
        var entry          = indices.buffer
        var checked        = 0'u32
        #static if Math.nativeToBigEndian(1'u16) != 1
        {
            const SwapWords = cast(Math.Simd.U8x16, [1'u8, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14])
            let blocks  = count / 8
            var largest = Math.Simd.splat(maxCustomIndex)
            for blocks
            {
                let words = cast #bit(Math.Simd.U16x8, Math.Simd.permute(Math.Simd.load(entry), SwapWords))
                largest = Math.Simd.select(words > largest, words, largest)
                entry   += 16
            }

            maxCustomIndex = Math.Simd.maximum(largest)
            checked        = cast(u32, blocks) * 8
        }

        for checked until count
        {
            maxCustomIndex = Math.max(maxCustomIndex, Math.make16(entry[0], entry[1]))
            entry += 2
        }

        let names        = &faceData.postNames
        let customCount  = cast(u64, maxCustomIndex) - 257
        let customOffset = 34 + cast(u64, count) * 2
        if customCount > postTable.count - customOffset do
            try fault(0x9B)

        names.postOffsets.allocator = Swag.getContext().allocator
        if customCount
        {
            names.postOffsets.reserve(customCount)
            let offsets = unwrap names.postOffsets.buffer
            let bytes   = postTable.buffer
            var offset  = customOffset
            var checked = 0'u64

            // Four Pascal strings fit within 1024 bytes, including their length bytes.
            while customCount - checked >= 4 and postTable.count - offset >= 1024
            {
                for lane in 4
                {
                    offsets[checked + lane] = cast(u32, offset)
                    offset += cast(u64, bytes[offset]) + 1
                }

                checked += 4
            }

            for index in checked until customCount
            {
                if offset >= postTable.count do
                    try fault(0x03)
                let length = postTable.buffer[offset]
                if length >= postTable.count - offset do
                    try fault(0x03)

                offsets[index] = cast(u32, offset)
                offset         += cast(u32, length) + 1
            }

            names.postOffsets.count = customCount
        }

        names.postStrings = postTable
        names.postIndices = indices
        return
    }

    if format == 0x00025000
    {
        let count = try readU16(postTable, 32)
        if count != glyphCount do
            try fault(0x9B)
        try assertRange(postTable, 34, count)
        faceData.postNames.entries.reserve(glyphCount)
        for glyphIndex in glyphCount
        {
            let offset    = cast(s8, try readU8(postTable, 34 + glyphIndex))
            let nameIndex = cast(s32, glyphIndex) + cast(s32, offset)
            if nameIndex < 0 or nameIndex >= MacStandardGlyphNames.count do
                try fault(0x9B)
            faceData.postNames.entries.add(MacStandardGlyphNames[cast(u32, nameIndex)])
        }
    }
}
