#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

// Computes a SHA-256 digest incrementally.
public struct Sha256
{
    internal
    {
        data:  [64] u8
        state: [8] u32 = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
                          0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19]
        dataLength: u32
        bitLength:  u64
    }
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
        func ch(x, y, z: u32)  => ((x & y) ^ (~x & z))
        func maj(x, y, z: u32) => ((x & y) ^ (x & z) ^ (y & z))
        func ep0(x: u32)       => (Swag.ror(x, 2) ^ Swag.ror(x, 13) ^ Swag.ror(x, 22))
        func ep1(x: u32)       => (Swag.ror(x, 6) ^ Swag.ror(x, 11) ^ Swag.ror(x, 25))
        func sig0(x: u32)      => (Swag.ror(x, 7) ^ Swag.ror(x, 18) ^ (x >> 3))
        func sig1(x: u32)      => (Swag.ror(x, 17) ^ Swag.ror(x, 19) ^ (x >> 10))
    }

    mtd transform(buf: const [*] u8)
    {
        var m: [64] u32

        let input = cast(const [*] u32, buf)
        for index in 16 do
            m[index] = Math.bigEndianToNative(input[index])

        var i = 16'u32
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
    // Stores a SHA-256 digest as eight 32-bit words.
    alias Digest = [8] u32

    // Finalizes the current sequence and returns its 256-bit digest.
    //
    // Call [[reset]] before reusing this value after finalization.
    mtd finalize()->Digest
    {
        .bitLength         += .dataLength * 8
        .data[.dataLength] = 0x80
        var used = .dataLength + 1
        if used > 56
        {
            Swag.memset(.data.buffer + used, 0, 64 - used)
            .transform(.data)
            used = 0
        }

        Swag.memset(.data.buffer + used, 0, 56 - used)
        cast([*] u64, .data.buffer)[7] = Math.nativeToBigEndian(.bitLength)
        .transform(.data)
        return .state
    }

    // Resets the sequence to the standard SHA-256 initial state.
    mtd reset()
    {
        Swag.init(me, 1)
    }

    // Includes `buffer` in the running digest.
    mtd update(buffer: const [..] u8)
    {
        var remaining = buffer.count
        if remaining == 0 do
            return
        var input = buffer.buffer

        if .dataLength
        {
            let copied = Math.min(remaining, 64 - cast(u64, .dataLength))
            Swag.memcpy(.data.buffer + .dataLength, input, copied)
            .dataLength += cast(u32, copied)
            if .dataLength < 64 do
                return

            .transform(.data)
            .bitLength  += 512
            .dataLength = 0
            input       += copied
            remaining   -= copied
        }

        while remaining >= 64
        {
            .transform(input)
            .bitLength += 512
            input      += 64
            remaining  -= 64
        }

        if remaining
        {
            Swag.memcpy(.data.buffer, input, remaining)
            .dataLength = cast(u32, remaining)
        }
    }

    // Computes the SHA-256 digest of `buffer` in one operation.
    func compute(buffer: const [..] u8)->Digest
    {
        var v: Sha256
        v.reset()
        v.update(buffer)
        return v.finalize()
    }
}

// Computes a SHA-224 digest incrementally.
public struct Sha224
{
    private core:        Sha256
    private initialized: bool
}

public impl Sha224
{
    // Stores a SHA-224 digest as seven 32-bit words in digest order.
    alias Digest = [7] u32

    // Resets the sequence to the SHA-224 initial state.
    mtd reset()
    {
        .core.reset()
        .core.state = [0xC1059ED8, 0x367CD507, 0x3070DD17, 0xF70E5939,
                       0xFFC00B31, 0x68581511, 0x64F98FA7, 0xBEFA4FA4]
        .initialized = true
    }

    // Includes `buffer` in the running digest.
    mtd update(buffer: const [..] u8)
    {
        if not .initialized do
            .reset()
        .core.update(buffer)
    }

    // Clears the current sequence state.
    mtd clear()
    {
        Swag.memset(me, 0, #sizeof(Sha224))
    }

    // Finalizes the current sequence and returns its 224-bit digest.
    mtd finalize()->Digest
    {
        if not .initialized do
            .reset()
        let fullDigest = .core.finalize()
        var result: #returntype
        for index in result.count do
            result[index] = fullDigest[index]
        return result
    }

    // Computes the SHA-224 digest of `buffer` in one operation.
    func compute(buffer: const [..] u8)->Digest
    {
        var hash: Sha224
        hash.reset()
        hash.update(buffer)
        return hash.finalize()
    }
}
