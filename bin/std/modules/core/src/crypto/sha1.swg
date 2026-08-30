#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

// Computes a SHA-1 digest incrementally.
//
// SHA-1 is suitable for compatibility and non-adversarial checksums only. Do not
// use it for signatures or other collision-resistant security decisions.
public struct Sha1
{
    internal
    {
        data:       [64] u8
        state:      [5] u32 = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        dataLength: u32
        bitLength:  u64
    }
}

impl Sha1
{
    #[Swag.Inline]
    {
        func rotLeft(a, b: u32) => ((a << b) | (a >> (32 - b)))
        func f1(x, y, z: u32)   => ((x & y) | (~x & z))
        func f2(x, y, z: u32)   => (x ^ y ^ z)
        func f3(x, y, z: u32)   => ((x & y) | (x & z) | (y & z))
        func f4(x, y, z: u32)   => (x ^ y ^ z)
    }

    // Process a single 512-bit block of data.
    // Performs the main SHA-1 compression function on the provided 'buf'.
    mtd transform(buf: const [*] u8)
    {
        var w: [80] u32

        var i, j = 0'u32
        while i < 16
        {
            w[i] = (cast(u32) buf[j] << 24) | (cast(u32) buf[j + 1] << 16) | (cast(u32) buf[j + 2] << 8) | buf[j + 3]
            i    += 1
            j    += 4
        }

        while i < 80
        {
            w[i] = rotLeft(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
            i    += 1
        }

        var a = .state[0]
        var b = .state[1]
        var c = .state[2]
        var d = .state[3]
        var e = .state[4]

        i = 0
        while i < 80
        {
            var f, k: u32
            if i < 20
            {
                f = f1(b, c, d)
                k = 0x5A827999
            }
            elif i < 40
            {
                f = f2(b, c, d)
                k = 0x6ED9EBA1
            }
            elif i < 60
            {
                f = f3(b, c, d)
                k = 0x8F1BBCDC
            }
            else
            {
                f = f4(b, c, d)
                k = 0xCA62C1D6
            }

            let temp = rotLeft(a, 5) + f + e + k + w[i]
            e = d
            d = c
            c = rotLeft(b, 30)
            b = a
            a = temp
            i += 1
        }

        .state[0] += a
        .state[1] += b
        .state[2] += c
        .state[3] += d
        .state[4] += e
    }
}

public impl Sha1
{
    // Stores a SHA-1 digest as five 32-bit words.
    alias Digest = [5] u32

    // Finalizes the current sequence and returns its 160-bit digest.
    // Call [[reset]] before reusing this value after finalization.
    mtd finalize()->Digest
    {
        var result: retval
        var i = .dataLength
        if .dataLength < 56
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

        .bitLength += .dataLength * 8
        .data[63]  = cast(u8) .bitLength
        .data[62]  = cast(u8) (.bitLength >> 8)
        .data[61]  = cast(u8) (.bitLength >> 16)
        .data[60]  = cast(u8) (.bitLength >> 24)
        .data[59]  = cast(u8) (.bitLength >> 32)
        .data[58]  = cast(u8) (.bitLength >> 40)
        .data[57]  = cast(u8) (.bitLength >> 48)
        .data[56]  = cast(u8) (.bitLength >> 56)
        .transform(.data)

        Memory.copy(result, &.state[0], #sizeof(.state))
        return result
    }

    // Resets the sequence to the standard SHA-1 initial state.
    mtd reset()
    {
        Swag.init(me, 1)
        .state[0] = 0x67452301
        .state[1] = 0xEFCDAB89
        .state[2] = 0x98BADCFE
        .state[3] = 0x10325476
        .state[4] = 0xC3D2E1F0
    }

    // Includes `buffer` in the running digest.
    mtd update(buffer: const [..] u8)
    {
        let buf = buffer.buffer
        let len = buffer.count

        for i in len
        {
            .data[.dataLength] = buf[i]
            .dataLength        += 1
            if .dataLength == 64
            {
                .transform(.data)
                .bitLength  += 512
                .dataLength = 0
            }
        }
    }

    // Computes the SHA-1 digest of `buffer` in one operation.
    func compute(buffer: const [..] u8)->Digest
    {
        var v: Sha1
        v.reset()
        v.update(buffer)
        return v.finalize()
    }
}
