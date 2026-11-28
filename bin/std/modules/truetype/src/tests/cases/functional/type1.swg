#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func buildBinaryType1Fixture(firstCipher: const [4] u8,
                             hexEncoded: bool = false,
                             rdSeparator: string = " ",
                             firstNotDefByte: u8 = 139,
                             bounds: string = "[0 0 1000 1000]")->Array!{u8}
{
    const HeaderPrefix               = "%!PS-AdobeFont-1.0: Fixture 1.0\n/FontName /Fixture\n/FontMatrix [0.001 0 0 0.001 0 0]\n/FontBBox"
    const HeaderSuffix               = "\n/Encoding StandardEncoding\neexec\n"
    const ClearPrivatePrefix: string = "/lenIV -1 def\n/CharStrings 2 dict dup begin\n/.notdef 4 RD"
    const ClearBetweenGlyphs: string = " ND\n/A 4 RD"
    const ClearPrivateSuffix: string = " ND\nend\n"
    var notDefCharstring: [4] u8 = [139, 139, 13, 14]
    const ACharstring: [4] u8 = [139, 189, 13, 14]
    notDefCharstring[0] = firstNotDefByte

    var plain: Array!{u8}
    plain.add(cast(const [..] u8, ClearPrivatePrefix))
    plain.add(cast(const [..] u8, rdSeparator))
    plain.add(notDefCharstring)
    plain.add(cast(const [..] u8, ClearBetweenGlyphs))
    plain.add(cast(const [..] u8, rdSeparator))
    plain.add(ACharstring)
    plain.add(cast(const [..] u8, ClearPrivateSuffix))

    var encrypted: Array!{u8}
    var state = 55665_u32
    for cipher in firstCipher
    {
        encrypted.add(cipher)
        state = ((cast(u32, cipher) + state) * 52845 + 22719) & 0xFFFF
    }

    for byte in plain
    {
        let cipher = byte ^ cast(u8, state >> 8)
        encrypted.add(cipher)
        state = ((cast(u32, cipher) + state) * 52845 + 22719) & 0xFFFF
    }

    var program: Array!{u8}
    program.add(cast(const [..] u8, HeaderPrefix))
    program.add(cast(const [..] u8, " "))
    program.add(cast(const [..] u8, bounds))
    program.add(cast(const [..] u8, HeaderSuffix))
    if hexEncoded
    {
        const HexDigits = "0123456789ABCDEF"
        var encoded: String
        for cipher in encrypted
        {
            encoded.append(HexDigits[cipher >> 4])
            encoded.append(HexDigits[cipher & 0x0F])
        }

        program.add(cast(const [..] u8, encoded.toString()))
        program.add(cast(const [..] u8, "\ncleartomark\n"))
    }
    else
    {
        program.add(encrypted.toSlice())
    }

    return program
}

// A binary eexec section can begin with bytes that happen to be ASCII hex digits.
#test
{
    const BinaryPrefix:     [4] u8 = [0x80, 0x81, 0x82, 0x83]
    const HexLookingPrefix: [4] u8 = ['A', '1', 'B', '2']

    let binaryFont = expect parseType1Font(buildBinaryType1Fixture(BinaryPrefix).toSlice())
    Swag.require(binaryFont.glyphNames.count == 2)

    let font = expect parseType1Font(buildBinaryType1Fixture(HexLookingPrefix).toSlice())
    Swag.require(font.glyphNames.count == 2)
    Swag.require(font.glyphNames[0] == ".notdef")
    Swag.require(font.glyphNames[1] == "A")

    let pfa = expect parseType1Font(buildBinaryType1Fixture(BinaryPrefix, true).toSlice())
    Swag.require(pfa.glyphNames.count == 2)

    var lowercase = buildBinaryType1Fixture(BinaryPrefix, true)
    let start     = findBytes(lowercase.toSlice(), 0, "eexec") + 5
    for index in start until lowercase.count
    {
        let c = lowercase[index]
        if c >= 'A' and c <= 'F'
        {
            lowercase[index] = c + 32
        }
    }

    let lower = expect parseType1Font(lowercase.toSlice())
    Swag.require(lower.glyphNames[1] == "A")
    Swag.require(expect type1CharstringWidth(&lower, 1) == 50)
}

#test
{
    const BinaryPrefix: [4] u8 = [0x80, 0x81, 0x82, 0x83]
    for bounds in ["[-11 -2e1 +9.55e2 870]", "% bounds\n{ -11% left\n -20 955 870 }"]
    {
        let bytes = buildBinaryType1Fixture(BinaryPrefix, bounds: bounds)
        let face  = expect Face.load(bytes.toSlice())
        defer face.destroy()

        let box = face.bbox
        Swag.require(box.xMin == -11 and box.yMin == -20 and box.xMax == 955 and box.yMax == 870)
        Swag.require(face.ascender == 870 and face.descender == -20 and face.height == 890)
    }

    for bounds in ["[1 2 3]", "{1 2 3 +}", "{1 2 3 4]", "{1 2 3 4 5}",
                   "{3 -20 1 870}", "{-11 -32768 955 32767}", "null\n/Later [4 5 6 7]"]
    {
        let bytes = buildBinaryType1Fixture(BinaryPrefix, bounds: bounds)
        let face  = expect Face.load(bytes.toSlice())
        defer face.destroy()

        let box = face.bbox
        Swag.require(box.xMin == 0 and box.yMin == 0 and box.xMax == 1000 and box.yMax == 1000)
    }
}

#test
{
    // Latin Modern Math Extension 10 uses a braced FontBBox in its PFB header.
    let face = expect Face.loadFile(getTestDataPath("latin-modern-extension-10.pfb"))
    defer face.destroy()

    // Design-space bounds and vertical metrics from FreeType 2.14.3.
    let box = face.bbox
    Swag.require(face.unitsPerEm == 1000)
    Swag.require(box.xMin == -24 and box.yMin == -2960 and box.xMax == 1454 and box.yMax == 772)
    Swag.require(face.ascender == 772 and face.descender == -2960 and face.height == 3732)
}

// CRLF after RD is consumed as one separator without discarding binary bytes.
#test
{
    const BinaryPrefix: [4] u8 = [0x80, 0x81, 0x82, 0x83]
    let bytes = buildBinaryType1Fixture(BinaryPrefix, rdSeparator: "\r\n")
    let font  = expect parseType1Font(bytes.toSlice())

    let notDef = font.codeOf(font.charstrings[0])
    Swag.require(notDef.count == 4)
    Swag.require(notDef[0] == 139 and notDef[1] == 139)
    Swag.require(notDef[2] == 13 and notDef[3] == 14)
    let glyph = font.codeOf(font.charstrings[1])
    Swag.require(glyph.count == 4)
    Swag.require(glyph[0] == 139 and glyph[1] == 189)
    Swag.require(glyph[2] == 13 and glyph[3] == 14)
}

// A lone separator leaves a whitespace-valued first charstring byte untouched.
#test
{
    const BinaryPrefix: [4] u8 = [0x80, 0x81, 0x82, 0x83]
    let bytes = buildBinaryType1Fixture(BinaryPrefix, firstNotDefByte: '\n')
    let font  = expect parseType1Font(bytes.toSlice())

    let notDef = font.codeOf(font.charstrings[0])
    Swag.require(notDef.count == 4)
    Swag.require(notDef[0] == '\n')
}

#test
{
    // PFB segment kinds are 1 (ASCII), 2 (binary), and 3 (end of file).
    const UnknownSegment: [6] u8 = [0x80, 0x04, 0x00, 0x00, 0x00, 0x00]
    var rejected: Swag.Error
    discard catch unwrapPfb(UnknownSegment) as rejected
    Swag.require(rejected.value() != null)
}

#test
{
    const CompletePfb: [9] u8 = [0x80, 0x01, 0x01, 0x00, 0x00, 0x00, 'A', 0x80, 0x03]
    let content = expect unwrapPfb(CompletePfb)
    Swag.require(content.count == 1 and content[0] == 'A')
}

#test
{
    // A complete PFB ends with its type-3 marker after the final data segment.
    const MissingEndMarker: [7] u8 = [0x80, 0x01, 0x01, 0x00, 0x00, 0x00, 'A']
    var rejected: Swag.Error
    discard catch unwrapPfb(MissingEndMarker) as rejected
    Swag.require(rejected.value() != null)
}

// A leading hsbw can be read directly. Computed widths and sbw use the interpreter.
#test
{
    const Direct:   [5] u8 = [139, 248, 136, 13, 14]
    const Division: [8] u8 = [139, 247, 92, 141, 12, 12, 13, 14]
    const Vector:   [7] u8 = [139, 139, 246, 139, 12, 7, 14]
    var font: Type1Font
    for code in [cast(const [..] u8, Direct), cast(const [..] u8, Division), cast(const [..] u8, Vector)]
    {
        font.charstrings.add(font.storeCode(code, -1))
    }

    let expected = [500.0, 100.0, 107.0]
    for width, gid in expected
    {
        let glyph = cast(u32, gid)
        Swag.require(expect type1CharstringWidth(&font, glyph) == width)
        Swag.require(expect runType1Charstring(&font, glyph, null) == width)
    }
}

// Retained Type 1 faces can outlive the source and share one parsed program.
#test
{
    const BinaryPrefix: [4] u8 = [0x80, 0x81, 0x82, 0x83]
    let bytes = buildBinaryType1Fixture(BinaryPrefix)
    var allocator: Swag.Allocator
    allocator.setup()
    defer allocator.releaseAll()
    let allocationView: IAllocator = &allocator
    let baseline = allocator.stats().countAlloc

    var source  = FontSource.copy(bytes.toSlice(), allocationView)
    let first   = expect source.loadFace()
    let second  = expect source.loadFace()
    let backing = cast(const *FaceImpl, cast(const *void, first))
    let sibling = cast(const *FaceImpl, cast(const *void, second))
    Swag.require(backing.sharedType1 != null and backing.sharedType1 == sibling.sharedType1)
    Swag.require(backing.sharedProgramTables != null and backing.sharedProgramTables == sibling.sharedProgramTables)
    source = {}
    first.destroy()
    Swag.require(second.glyphIndex('A') == 1 and second.glyphName(1) == "A")
    Swag.require(expect second.getAdvanceWidth(1) == 50)
    second.destroy()
    Swag.require(allocator.stats().countAlloc == baseline)
}

// Whole vectors and their remainders must carry the same state after leading padding.
#test
{
    var ciphertext: [65] u8
    for index in ciphertext.count
    {
        ciphertext[index] = cast(u8, (index * 91 + index * index * 17) & 0xFF)
    }

    for key in [0_u16, 4330, 55665, Swag.U16.Max]
    {
        var cleartext: [65] u8
        var state = cast(u32, key)
        for index in ciphertext.count
        {
            let cipher = ciphertext[index]
            cleartext[index] = cipher ^ cast(u8, (state >> 8) & 0xFF)
            state = ((state + cipher) * 52845 + 22719) & 0xFFFF
        }

        for size in [0_u64, 1, 15, 16, 17, 31, 32, 33, 64, 65]
        {
            for skip in [0_u64, 1, 4, 9, 16]
            {
                let decoded = eexecDecrypt(ciphertext[0 until size], key, skip)
                let start   = Math.min(size, skip)
                Swag.require(Slice.equals(decoded.toSlice(), cleartext[start until size]))
            }
        }
    }
}
