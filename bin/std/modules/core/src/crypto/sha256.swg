#global namespace Hash
#global #[Swag.CanOverflow(true)]

public struct Sha256
{
    data:    [64] u8
    state:   [8] u32
    datalen: u32
    bitlen:  u64
}

impl Sha256
{
    const K: [64] u32 = [
        0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
        0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
        0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
        0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
        0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
        0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
        0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
        0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2]

    #[Swag.Inline]
    {
        func rotLeft(a, b: u32)  => ((a << b) | (a >> (32 - b)))
        func rotRight(a, b: u32) => ((a >> b) | (a << (32 - b)))
        func ch(x, y, z: u32)    => ((x & y) ^ (~x & z))
        func maj(x, y, z: u32)   => ((x & y) ^ (x & z) ^ (y & z))
        func ep0(x: u32)         => (rotRight(x, 2) ^ rotRight(x, 13) ^ rotRight(x, 22))
        func ep1(x: u32)         => (rotRight(x, 6) ^ rotRight(x, 11) ^ rotRight(x, 25))
        func sig0(x: u32)        => (rotRight(x, 7) ^ rotRight(x, 18) ^ (x >> 3))
        func sig1(x: u32)        => (rotRight(x, 17) ^ rotRight(x, 19) ^ (x >> 10))
    }

    mtd transform(buf: const [*] u8)
    {
        var m: [64] u32

        var i, j = 0'u32
        while i < 16
        {
            m[i] = (cast(u32) buf[j] << 24) | (cast(u32) buf[j + 1] << 16) | (cast(u32) buf[j + 2] << 8) | buf[j + 3]
            i    += 1
            j    += 4
        }

        while i < 64
        {
            m[i] = sig1(m[i - 2]) + m[i - 7] + sig0(m[i - 15]) + m[i - 16]
            i    += 1
        }

        var a = .state[0]
        var b = .state[1]
        var c = .state[2]
        var d = .state[3]
        var e = .state[4]
        var f = .state[5]
        var g = .state[6]
        var h = .state[7]

        i = 0
        while i < 64
        {
            let t1 = h + ep1(e) + ch(e, f, g) + K[i] + m[i]
            let t2 = ep0(a) + maj(a, b, c)
            h = g
            g = f
            f = e
            e = d + t1
            d = c
            c = b
            b = a
            a = t1 + t2
            i += 1
        }

        .state[0] += a
        .state[1] += b
        .state[2] += c
        .state[3] += d
        .state[4] += e
        .state[5] += f
        .state[6] += g
        .state[7] += h
    }
}

public impl Sha256
{
    alias Digest = [8] u32

    // Finalize the computation
    mtd final(result: Digest)
    {
        var i = .datalen
        if .datalen < 56
        {
            .data[i] = 0x80
            i        += 1
            while i < 56
            {
                .data[i] = 0x00
                i        += 1
            }
        }
        else
        {
            .data[i] = 0x80
            i        += 1
            while i < 64
            {
                .data[i] = 0x00
                i        += 1
            }

            .transform(.data)

            i = 0
            while i < 56
            {
                .data[i] = 0x00
                i        += 1
            }
        }

        .bitlen   += .datalen * 8
        .data[63] = cast(u8) .bitlen
        .data[62] = cast(u8) (.bitlen >> 8)
        .data[61] = cast(u8) (.bitlen >> 16)
        .data[60] = cast(u8) (.bitlen >> 24)
        .data[59] = cast(u8) (.bitlen >> 32)
        .data[58] = cast(u8) (.bitlen >> 40)
        .data[57] = cast(u8) (.bitlen >> 48)
        .data[56] = cast(u8) (.bitlen >> 56)
        .transform(.data)

        Memory.copy(result, &.state[0], #sizeof(.state))
    }

    // Initialize the hashing sequence
    mtd init()
    {
        @init(me, 1)
        .state[0] = 0x6A09E667
        .state[1] = 0xBB67AE85
        .state[2] = 0x3C6EF372
        .state[3] = 0xA54FF53A
        .state[4] = 0x510E527F
        .state[5] = 0x9B05688C
        .state[6] = 0x1F83D9AB
        .state[7] = 0x5BE0CD19
    }

    // Update the hash value with 'buffer' content
    mtd update(buffer: const [..] u8)
    {
        Debug.assert(@countof(buffer) <= Swag.U32.Max)
        let buf = @dataof(buffer)
        let len = cast(u32) @countof(buffer)

        for i in len
        {
            .data[.datalen] = buf[i]
            .datalen        += 1
            if .datalen == 64
            {
                .transform(.data)
                .bitlen  += 512
                .datalen = 0
            }
        }
    }

    // Returns the sha256 value for the given buffer
    func compute(buffer: const [..] u8)->Digest
    {
        var v: Sha256
        v.init()
        v.update(buffer)

        var result: retval
        v.final(result)
        return result
    }
}
