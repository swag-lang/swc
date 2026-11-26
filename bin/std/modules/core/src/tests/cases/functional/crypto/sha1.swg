#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func assertSha1Digest(digest: Hash.Sha1.Digest, e0, e1, e2, e3, e4: u32)
{
    Swag.require(digest[0] == e0)
    Swag.require(digest[1] == e1)
    Swag.require(digest[2] == e2)
    Swag.require(digest[3] == e3)
    Swag.require(digest[4] == e4)
}

func assertSha1(buffer: const [..] u8, e0, e1, e2, e3, e4: u32)
{
    assertSha1Digest(Hash.Sha1.compute(buffer), e0, e1, e2, e3, e4)

    var sha: Hash.Sha1
    sha.reset()
    sha.update(buffer)

    var digest: Hash.Sha1.Digest
    digest = sha.finalize()
    assertSha1Digest(digest, e0, e1, e2, e3, e4)

    sha.reset()
    sha.update("")
    sha.update(buffer)
    sha.update("")
    digest = sha.finalize()
    assertSha1Digest(digest, e0, e1, e2, e3, e4)
}

func fillSha1Pattern(buffer: [..] u8)
{
    var i = 0_u64
    while i < buffer.count
    {
        buffer[i] = cast(u8, ((i * 37 + 11) & 0xFF))
        i         += 1
    }
}

#test
{
    assertSha1("", 0xDA39A3EE_u32, 0x5E6B4B0D_u32, 0x3255BFEF_u32, 0x95601890_u32, 0xAFD80709_u32)
    assertSha1("abc", 0xA9993E36_u32, 0x4706816A_u32, 0xBA3E2571_u32, 0x7850C26C_u32, 0x9CD0D89D_u32)
    assertSha1("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 0x84983E44_u32, 0x1C3BD26E_u32, 0xBAAE4AA1_u32, 0xF95129E5_u32, 0xE54670F1_u32)

    var data: [128] u8
    fillSha1Pattern(data)

    assertSha1(data[until 0], 0xDA39A3EE_u32, 0x5E6B4B0D_u32, 0x3255BFEF_u32, 0x95601890_u32, 0xAFD80709_u32)
    assertSha1(data[until 1], 0x067D5096_u32, 0xF219C64B_u32, 0x53BB1C7D_u32, 0x5E375428_u32, 0x5B565A47_u32)
    assertSha1(data[until 3], 0x5E8B290F_u32, 0x00D31C34_u32, 0x1D769E40_u32, 0x255C7579_u32, 0x24864EF3_u32)
    assertSha1(data[until 55], 0xC4622048_u32, 0xCFEF59B7_u32, 0x2875839E_u32, 0xE7AE1CBC_u32, 0xF55E7658_u32)
    assertSha1(data[until 56], 0xDDC12942_u32, 0x65646847_u32, 0x5970FA4F_u32, 0xA49161F5_u32, 0x2ED138E4_u32)
    assertSha1(data[until 57], 0xC3299DF7_u32, 0xD6A56509_u32, 0xD38A55D0_u32, 0x9CCF403D_u32, 0x4A56D044_u32)
    assertSha1(data[until 63], 0x7F8C3FA4_u32, 0x9F1297BD_u32, 0x8B9FEB96_u32, 0x4B6B4199_u32, 0x87F9F0D1_u32)
    assertSha1(data[until 64], 0xA334B471_u32, 0x80C61FD5_u32, 0x22F99905_u32, 0xEC02C36F_u32, 0x9E848211_u32)
    assertSha1(data[until 65], 0xDD27D9EB_u32, 0x923D3968_u32, 0x7E10872C_u32, 0x3E8133BA_u32, 0x2F0A68A1_u32)
    assertSha1(data[until 127], 0xB2B4BFD7_u32, 0xB2112A16_u32, 0x7B77A600_u32, 0xCCA22759_u32, 0x3523C406_u32)
    assertSha1(data[until 128], 0x3B195309_u32, 0x18994923_u32, 0x77F686C2_u32, 0x66B81D84_u32, 0xB5D40F70_u32)
    assertSha1(data[1 until 65], 0x2C7464CA_u32, 0x06177AB7_u32, 0xBB992214_u32, 0x57805B4E_u32, 0xF1366801_u32)

    var split: Hash.Sha1
    split.reset()
    split.update(data[until 1])
    split.update(data[1 until 55])
    split.update(data[55 until 64])
    split.update(data[64 until 128])

    var digest: Hash.Sha1.Digest
    digest = split.finalize()
    assertSha1Digest(digest, 0x3B195309_u32, 0x18994923_u32, 0x77F686C2_u32, 0x66B81D84_u32, 0xB5D40F70_u32)
}

#test
{
    if not Swag.hasCpuFeature(.Sha)
    {
        return
    }

    var data: [257] u8
    fillSha1Pattern(data)

    var hardware, software: Hash.Sha1
    for blocks in 1 until 5
    {
        hardware.reset()
        software.reset()
        hardware.transformShaExtensions(data.buffer + 1, blocks)
        for block in blocks
        {
            software.transformPortable(data.buffer + 1 + block * 64)
        }

        for index in hardware.state.count
        {
            Swag.require(hardware.state[index] == software.state[index])
        }
    }
}
