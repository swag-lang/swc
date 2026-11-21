#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func buildBinaryType1Fixture(firstCipher: const [4] u8, hexEncoded: bool = false)->Array'u8
{
    const ClearHeader: string = "%!PS-AdobeFont-1.0: Fixture 1.0\n/FontName /Fixture\n/FontMatrix [0.001 0 0 0.001 0 0]\n/FontBBox [0 0 1000 1000]\n/Encoding StandardEncoding\neexec\n"
    const ClearPrivatePrefix: string = "/lenIV -1 def\n/CharStrings 2 dict dup begin\n/.notdef 4 RD "
    const ClearBetweenGlyphs: string = " ND\n/A 4 RD "
    const ClearPrivateSuffix: string = " ND\nend\n"
    const NotDefCharstring: [4] u8 = [139, 139, 13, 14]
    const ACharstring: [4] u8 = [139, 189, 13, 14]

    var plain: Array'u8
    plain.add(cast(const [..] u8, ClearPrivatePrefix))
    plain.add(NotDefCharstring)
    plain.add(cast(const [..] u8, ClearBetweenGlyphs))
    plain.add(ACharstring)
    plain.add(cast(const [..] u8, ClearPrivateSuffix))

    var encrypted: Array'u8
    var state = 55665'u32
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

    var program: Array'u8
    program.add(cast(const [..] u8, ClearHeader))
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
    const BinaryPrefix: [4] u8 = [0x80, 0x81, 0x82, 0x83]
    const HexLookingPrefix: [4] u8 = ['A', '1', 'B', '2']

    let binaryFont = expect parseType1Font(buildBinaryType1Fixture(BinaryPrefix).toSlice())
    Swag.require(binaryFont.glyphNames.count == 2)

    let font = expect parseType1Font(buildBinaryType1Fixture(HexLookingPrefix).toSlice())
    Swag.require(font.glyphNames.count == 2)
    Swag.require(font.glyphNames[0].toString() == ".notdef")
    Swag.require(font.glyphNames[1].toString() == "A")

    let pfa = expect parseType1Font(buildBinaryType1Fixture(BinaryPrefix, true).toSlice())
    Swag.require(pfa.glyphNames.count == 2)
}

#test
{
    // PFB segment kinds are 1 (ASCII), 2 (binary), and 3 (end of file).
    const UnknownSegment: [6] u8 = [0x80, 0x04, 0x00, 0x00, 0x00, 0x00]
    var rejected: Swag.Error
    discard catch unwrapPfb(UnknownSegment) as rejected
    Swag.require(rejected.value() != null)
}
