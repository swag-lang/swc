#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertSha256Digest(digest: Hash.Sha256.Digest, e0, e1, e2, e3, e4, e5, e6, e7: u32)
{
    Swag.require(digest[0] == e0)
    Swag.require(digest[1] == e1)
    Swag.require(digest[2] == e2)
    Swag.require(digest[3] == e3)
    Swag.require(digest[4] == e4)
    Swag.require(digest[5] == e5)
    Swag.require(digest[6] == e6)
    Swag.require(digest[7] == e7)
}

func assertSha256(buffer: const [..] u8, e0, e1, e2, e3, e4, e5, e6, e7: u32)
{
    assertSha256Digest(Hash.Sha256.compute(buffer), e0, e1, e2, e3, e4, e5, e6, e7)

    var sha: Hash.Sha256
    sha.reset()
    sha.update(buffer)

    var digest: Hash.Sha256.Digest
    digest = sha.finalize()
    assertSha256Digest(digest, e0, e1, e2, e3, e4, e5, e6, e7)

    sha.reset()
    sha.update("")
    sha.update(buffer)
    sha.update("")
    digest = sha.finalize()
    assertSha256Digest(digest, e0, e1, e2, e3, e4, e5, e6, e7)
}

func fillSha256Pattern(buffer: [..] u8)
{
    var i = 0_u64
    while i < buffer.count
    {
        buffer[i] = cast(u8, ((i * 37 + 11) & 0xFF))
        i         += 1
    }
}

func sha224HexDigit(value: u8)->u8
{
    if value >= '0' and value <= '9'
    {
        return value - '0'
    }

    return (value - 'a') + 10
}

func sha224HexBytes(text: string)->Array!{u8}
{
    var result: #returntype
    result.reserve(text.count / 2)
    var index = 0_u64
    while index + 1 < text.count
    {
        result.add(cast(u8, ((sha224HexDigit(text[index]) << 4) | sha224HexDigit(text[index + 1]))))
        index += 2
    }

    return result
}

func sha224DigestBytes(digest: Hash.Sha224.Digest)->[28] u8
{
    var result: #returntype
    for index in digest.count
    {
        for byte in 4
        {
            result[index * 4 + byte] = Math.byteAt(digest[index], 3 - byte)
        }
    }

    return result
}

#test
{
    assertSha256("", 0xE3B0C442_u32, 0x98FC1C14_u32, 0x9AFBF4C8_u32, 0x996FB924_u32, 0x27AE41E4_u32, 0x649B934C_u32, 0xA495991B_u32, 0x7852B855_u32)
    assertSha256("abc", 0xBA7816BF_u32, 0x8F01CFEA_u32, 0x414140DE_u32, 0x5DAE2223_u32, 0xB00361A3_u32, 0x96177A9C_u32, 0xB410FF61_u32, 0xF20015AD_u32)
    assertSha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 0x248D6A61_u32, 0xD20638B8_u32, 0xE5C02693_u32, 0x0C3E6039_u32, 0xA33CE459_u32, 0x64FF2167_u32, 0xF6ECEDD4_u32, 0x19DB06C1_u32)

    var data: [128] u8
    fillSha256Pattern(data)

    assertSha256(data[until 0], 0xE3B0C442_u32, 0x98FC1C14_u32, 0x9AFBF4C8_u32, 0x996FB924_u32, 0x27AE41E4_u32, 0x649B934C_u32, 0xA495991B_u32, 0x7852B855_u32)
    assertSha256(data[until 1], 0xE7CF46A0_u32, 0x78FED4FA_u32, 0xFD0B5E3A_u32, 0xFF144802_u32, 0xB853F8AE_u32, 0x459A4F0C_u32, 0x14ADD331_u32, 0x4B7CC3A6_u32)
    assertSha256(data[until 3], 0xB39FAD1A_u32, 0x1075F645_u32, 0x70B3226D_u32, 0x339EA818_u32, 0xF9C66ECD_u32, 0x2F1C59FD_u32, 0x8B9C5A32_u32, 0xB54C513F_u32)
    assertSha256(data[until 55], 0x2900465F_u32, 0xCB533E05_u32, 0xA158FD2B_u32, 0x3BE0E5E3_u32, 0xB03740D8_u32, 0x3060AA35_u32, 0x80E0D98A_u32, 0x96BF2384_u32)
    assertSha256(data[until 56], 0x31454FF4_u32, 0x8EF36AF2_u32, 0xF08FD511_u32, 0xBDC37D9D_u32, 0x5855AC23_u32, 0xE992E5FF_u32, 0x5445CB6B_u32, 0x7674A674_u32)
    assertSha256(data[until 57], 0xBCC0A5D3_u32, 0x791B985B_u32, 0x7550E04C_u32, 0xA660A6C6_u32, 0x3A589BA1_u32, 0xEDD2283C_u32, 0x8E110E5B_u32, 0x515DF124_u32)
    assertSha256(data[until 63], 0x5F6401B9_u32, 0x6532C36D_u32, 0xE4E65BEE_u32, 0xC0409B69_u32, 0xB1D18186_u32, 0x4C8009B7_u32, 0xA04F43E5_u32, 0xD56350D1_u32)
    assertSha256(data[until 64], 0x94EB5DE4_u32, 0x943613FD_u32, 0x048DC933_u32, 0x93AB0687_u32, 0x7405FAA3_u32, 0x9C11F53E_u32, 0x93860833_u32, 0x39833E7E_u32)
    assertSha256(data[until 65], 0xFC518669_u32, 0xB6EB4B4D_u32, 0xD91827EC_u32, 0xACEF8668_u32, 0x9C725BD5_u32, 0xBAB888FD_u32, 0x3B26DBB1_u32, 0x96EEC954_u32)
    assertSha256(data[until 127], 0x0FE729FF_u32, 0x19257BD6_u32, 0xFEC853AC_u32, 0xC2EA355F_u32, 0x6B34B58E_u32, 0x6C0F684C_u32, 0x3E188FCD_u32, 0xFCD9BAAE_u32)
    assertSha256(data[until 128], 0x0AEDD485_u32, 0x6F8EBA09_u32, 0x63627336_u32, 0xAD5144A9_u32, 0xA7DBE124_u32, 0x98E6066F_u32, 0x0165FC97_u32, 0xD8DDEE4C_u32)
    assertSha256(data[1 until 65], 0x5C6365B0_u32, 0x0593F37D_u32, 0x2827A1EB_u32, 0xE20E6240_u32, 0x762D398B_u32, 0xB414F1E1_u32, 0x5FF8694C_u32, 0xF9FD69B9_u32)

    var split: Hash.Sha256
    split.reset()
    split.update(data[until 1])
    split.update(data[1 until 55])
    split.update(data[55 until 64])
    split.update(data[64 until 128])

    var digest: Hash.Sha256.Digest
    digest = split.finalize()
    assertSha256Digest(digest, 0x0AEDD485_u32, 0x6F8EBA09_u32, 0x63627336_u32, 0xAD5144A9_u32, 0xA7DBE124_u32, 0x98E6066F_u32, 0x0165FC97_u32, 0xD8DDEE4C_u32)
}

#test
{
    let emptyDigest = sha224DigestBytes(Hash.Sha224.compute(""))
    let abcDigest   = sha224DigestBytes(Hash.Sha224.compute("abc"))
    Swag.require(Crypto.constantTimeEqual(emptyDigest, sha224HexBytes("d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f").toSlice()))
    Swag.require(Crypto.constantTimeEqual(abcDigest, sha224HexBytes("23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7").toSlice()))

    var input: [128] u8
    for index in input.count
    {
        input[index] = cast(u8, (index * 37 + 11) & 0xFF)
    }

    let expected = Hash.Sha224.compute(input)
    for split in [0_u64, 1, 55, 56, 63, 64, 65, 127, 128]
    {
        var incremental: Hash.Sha224
        incremental.update(input[until split])
        incremental.update(input[split to])
        Swag.require(Crypto.constantTimeEqual(sha224DigestBytes(incremental.finalize()), sha224DigestBytes(expected)))
    }
}

#test
{
    if not Swag.hasCpuFeature(.Sha) do
        return

    var data: [257] u8
    fillSha256Pattern(data)

    var hardware, software: Hash.Sha256
    for blocks in 1 until 5
    {
        hardware.reset()
        software.reset()
        hardware.transformShaExtensions(data.buffer + 1, blocks)
        for block in blocks do
            software.transformPortable(data.buffer + 1 + block * 64)

        for index in hardware.state.count do
            Swag.require(hardware.state[index] == software.state[index])
    }
}
