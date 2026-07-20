#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertSha256Digest(digest: Hash.Sha256.Digest, e0, e1, e2, e3, e4, e5, e6, e7: u32)
{
    @assert(digest[0] == e0)
    @assert(digest[1] == e1)
    @assert(digest[2] == e2)
    @assert(digest[3] == e3)
    @assert(digest[4] == e4)
    @assert(digest[5] == e5)
    @assert(digest[6] == e6)
    @assert(digest[7] == e7)
}

func assertSha256(buffer: const [..] u8, e0, e1, e2, e3, e4, e5, e6, e7: u32)
{
    assertSha256Digest(Hash.Sha256.compute(buffer), e0, e1, e2, e3, e4, e5, e6, e7)

    var sha: Hash.Sha256
    sha.init()
    sha.update(buffer)

    var digest: Hash.Sha256.Digest
    sha.final(digest)
    assertSha256Digest(digest, e0, e1, e2, e3, e4, e5, e6, e7)

    sha.init()
    sha.update("")
    sha.update(buffer)
    sha.update("")
    sha.final(digest)
    assertSha256Digest(digest, e0, e1, e2, e3, e4, e5, e6, e7)
}

func fillSha256Pattern(buffer: [..] u8)
{
    var i = 0'u64
    while i < @countof(buffer)
    {
        buffer[i] = cast(u8) ((i * 37 + 11) & 0xff)
        i += 1
    }
}

#test
{
    assertSha256("", 0xE3B0C442'u32, 0x98FC1C14'u32, 0x9AFBF4C8'u32, 0x996FB924'u32, 0x27AE41E4'u32, 0x649B934C'u32, 0xA495991B'u32, 0x7852B855'u32)
    assertSha256("abc", 0xBA7816BF'u32, 0x8F01CFEA'u32, 0x414140DE'u32, 0x5DAE2223'u32, 0xB00361A3'u32, 0x96177A9C'u32, 0xB410FF61'u32, 0xF20015AD'u32)
    assertSha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 0x248D6A61'u32, 0xD20638B8'u32, 0xE5C02693'u32, 0x0C3E6039'u32, 0xA33CE459'u32, 0x64FF2167'u32, 0xF6ECEDD4'u32, 0x19DB06C1'u32)

    var data: [128] u8
    fillSha256Pattern(data)

    assertSha256(data[until 0], 0xE3B0C442'u32, 0x98FC1C14'u32, 0x9AFBF4C8'u32, 0x996FB924'u32, 0x27AE41E4'u32, 0x649B934C'u32, 0xA495991B'u32, 0x7852B855'u32)
    assertSha256(data[until 1], 0xE7CF46A0'u32, 0x78FED4FA'u32, 0xFD0B5E3A'u32, 0xFF144802'u32, 0xB853F8AE'u32, 0x459A4F0C'u32, 0x14ADD331'u32, 0x4B7CC3A6'u32)
    assertSha256(data[until 3], 0xB39FAD1A'u32, 0x1075F645'u32, 0x70B3226D'u32, 0x339EA818'u32, 0xF9C66ECD'u32, 0x2F1C59FD'u32, 0x8B9C5A32'u32, 0xB54C513F'u32)
    assertSha256(data[until 55], 0x2900465F'u32, 0xCB533E05'u32, 0xA158FD2B'u32, 0x3BE0E5E3'u32, 0xB03740D8'u32, 0x3060AA35'u32, 0x80E0D98A'u32, 0x96BF2384'u32)
    assertSha256(data[until 56], 0x31454FF4'u32, 0x8EF36AF2'u32, 0xF08FD511'u32, 0xBDC37D9D'u32, 0x5855AC23'u32, 0xE992E5FF'u32, 0x5445CB6B'u32, 0x7674A674'u32)
    assertSha256(data[until 57], 0xBCC0A5D3'u32, 0x791B985B'u32, 0x7550E04C'u32, 0xA660A6C6'u32, 0x3A589BA1'u32, 0xEDD2283C'u32, 0x8E110E5B'u32, 0x515DF124'u32)
    assertSha256(data[until 63], 0x5F6401B9'u32, 0x6532C36D'u32, 0xE4E65BEE'u32, 0xC0409B69'u32, 0xB1D18186'u32, 0x4C8009B7'u32, 0xA04F43E5'u32, 0xD56350D1'u32)
    assertSha256(data[until 64], 0x94EB5DE4'u32, 0x943613FD'u32, 0x048DC933'u32, 0x93AB0687'u32, 0x7405FAA3'u32, 0x9C11F53E'u32, 0x93860833'u32, 0x39833E7E'u32)
    assertSha256(data[until 65], 0xFC518669'u32, 0xB6EB4B4D'u32, 0xD91827EC'u32, 0xACEF8668'u32, 0x9C725BD5'u32, 0xBAB888FD'u32, 0x3B26DBB1'u32, 0x96EEC954'u32)
    assertSha256(data[until 127], 0x0FE729FF'u32, 0x19257BD6'u32, 0xFEC853AC'u32, 0xC2EA355F'u32, 0x6B34B58E'u32, 0x6C0F684C'u32, 0x3E188FCD'u32, 0xFCD9BAAE'u32)
    assertSha256(data[until 128], 0x0AEDD485'u32, 0x6F8EBA09'u32, 0x63627336'u32, 0xAD5144A9'u32, 0xA7DBE124'u32, 0x98E6066F'u32, 0x0165FC97'u32, 0xD8DDEE4C'u32)
    assertSha256(data[1 until 65], 0x5C6365B0'u32, 0x0593F37D'u32, 0x2827A1EB'u32, 0xE20E6240'u32, 0x762D398B'u32, 0xB414F1E1'u32, 0x5FF8694C'u32, 0xF9FD69B9'u32)

    var split: Hash.Sha256
    split.init()
    split.update(data[until 1])
    split.update(data[1 until 55])
    split.update(data[55 until 64])
    split.update(data[64 until 128])

    var digest: Hash.Sha256.Digest
    split.final(digest)
    assertSha256Digest(digest, 0x0AEDD485'u32, 0x6F8EBA09'u32, 0x63627336'u32, 0xAD5144A9'u32, 0xA7DBE124'u32, 0x98E6066F'u32, 0x0165FC97'u32, 0xD8DDEE4C'u32)
}
