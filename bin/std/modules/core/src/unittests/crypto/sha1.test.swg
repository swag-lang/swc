#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

func assertSha1Digest(digest: Hash.Sha1.Digest, e0, e1, e2, e3, e4: u32)
{
    @assert(digest[0] == e0)
    @assert(digest[1] == e1)
    @assert(digest[2] == e2)
    @assert(digest[3] == e3)
    @assert(digest[4] == e4)
}

func assertSha1(buffer: #nonull const [..] u8, e0, e1, e2, e3, e4: u32)
{
    assertSha1Digest(Hash.Sha1.compute(buffer), e0, e1, e2, e3, e4)

    var sha: Hash.Sha1
    sha.init()
    sha.update(buffer)

    var digest: Hash.Sha1.Digest
    sha.final(digest)
    assertSha1Digest(digest, e0, e1, e2, e3, e4)

    sha.init()
    sha.update("")
    sha.update(buffer)
    sha.update("")
    sha.final(digest)
    assertSha1Digest(digest, e0, e1, e2, e3, e4)
}

func fillSha1Pattern(buffer: #nonull [..] u8)
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
    assertSha1("", 0xDA39A3EE'u32, 0x5E6B4B0D'u32, 0x3255BFEF'u32, 0x95601890'u32, 0xAFD80709'u32)
    assertSha1("abc", 0xA9993E36'u32, 0x4706816A'u32, 0xBA3E2571'u32, 0x7850C26C'u32, 0x9CD0D89D'u32)
    assertSha1("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq", 0x84983E44'u32, 0x1C3BD26E'u32, 0xBAAE4AA1'u32, 0xF95129E5'u32, 0xE54670F1'u32)

    var data: [128] u8
    fillSha1Pattern(data)

    assertSha1(data[until 0], 0xDA39A3EE'u32, 0x5E6B4B0D'u32, 0x3255BFEF'u32, 0x95601890'u32, 0xAFD80709'u32)
    assertSha1(data[until 1], 0x067D5096'u32, 0xF219C64B'u32, 0x53BB1C7D'u32, 0x5E375428'u32, 0x5B565A47'u32)
    assertSha1(data[until 3], 0x5E8B290F'u32, 0x00D31C34'u32, 0x1D769E40'u32, 0x255C7579'u32, 0x24864EF3'u32)
    assertSha1(data[until 55], 0xC4622048'u32, 0xCFEF59B7'u32, 0x2875839E'u32, 0xE7AE1CBC'u32, 0xF55E7658'u32)
    assertSha1(data[until 56], 0xDDC12942'u32, 0x65646847'u32, 0x5970FA4F'u32, 0xA49161F5'u32, 0x2ED138E4'u32)
    assertSha1(data[until 57], 0xC3299DF7'u32, 0xD6A56509'u32, 0xD38A55D0'u32, 0x9CCF403D'u32, 0x4A56D044'u32)
    assertSha1(data[until 63], 0x7F8C3FA4'u32, 0x9F1297BD'u32, 0x8B9FEB96'u32, 0x4B6B4199'u32, 0x87F9F0D1'u32)
    assertSha1(data[until 64], 0xA334B471'u32, 0x80C61FD5'u32, 0x22F99905'u32, 0xEC02C36F'u32, 0x9E848211'u32)
    assertSha1(data[until 65], 0xDD27D9EB'u32, 0x923D3968'u32, 0x7E10872C'u32, 0x3E8133BA'u32, 0x2F0A68A1'u32)
    assertSha1(data[until 127], 0xB2B4BFD7'u32, 0xB2112A16'u32, 0x7B77A600'u32, 0xCCA22759'u32, 0x3523C406'u32)
    assertSha1(data[until 128], 0x3B195309'u32, 0x18994923'u32, 0x77F686C2'u32, 0x66B81D84'u32, 0xB5D40F70'u32)
    assertSha1(data[1 until 65], 0x2C7464CA'u32, 0x06177AB7'u32, 0xBB992214'u32, 0x57805B4E'u32, 0xF1366801'u32)

    var split: Hash.Sha1
    split.init()
    split.update(data[until 1])
    split.update(data[1 until 55])
    split.update(data[55 until 64])
    split.update(data[64 until 128])

    var digest: Hash.Sha1.Digest
    split.final(digest)
    assertSha1Digest(digest, 0x3B195309'u32, 0x18994923'u32, 0x77F686C2'u32, 0x66B81D84'u32, 0xB5D40F70'u32)
}
