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
        func f1(x, y, z: u32) => ((x & y) | (~x & z))
        func f2(x, y, z: u32) => (x ^ y ^ z)
        func f3(x, y, z: u32) => ((x & y) | (x & z) | (y & z))
        func f4(x, y, z: u32) => (x ^ y ^ z)
    }

    // Compresses the complete 512-bit blocks at `buf`.
    mtd transformBlocks(buf: const [*] u8, blocks: u64)
    {
        if Swag.hasCpuFeature(.Sha)
        {
            .transformShaExtensions(buf, blocks)
            return
        }

        var input = buf
        for blocks
        {
            .transformPortable(input)
            input += 64
        }
    }

    mtd transformShaExtensions(buf: const [*] u8, blocks: u64)
    {
        using Math

        #[Swag.Inline]
        func(phase: u8) advance(words: Simd.U32x4, abcd, previous: *Simd.U32x4)
        {
            let withE = Swag.vecSha1NextE(previous[], words)
            previous[] = abcd[]
            abcd[]     = Swag.vecSha1Rounds4(abcd[], withE, phase)
        }

        #[Swag.Inline]
        func extend(oldest, older, newer, newest: Simd.U32x4)->Simd.U32x4
        {
            let partial = Swag.vecSha1Schedule1(oldest, older) ^ newer
            return Swag.vecSha1Schedule2(partial, newest)
        }

        const ReverseWords = cast(Simd.U32x4, [3'u32, 2, 1, 0])
        const ReverseBytes = cast(Simd.U8x16, [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
        var abcd  = Simd.permute(Simd.load(.state.buffer), ReverseWords)
        var e     = cast(Simd.U32x4, [0'u32, 0, 0, .state[4]])
        var input = buf
        for blocks
        {
            let savedAbcd = abcd
            var previous  = abcd
            var w0        = cast #bit (Simd.U32x4, Simd.shuffle(Simd.load(input), ReverseBytes))
            var w1        = cast #bit (Simd.U32x4, Simd.shuffle(Simd.load(input + 16), ReverseBytes))
            var w2        = cast #bit (Simd.U32x4, Simd.shuffle(Simd.load(input + 32), ReverseBytes))
            var w3        = cast #bit (Simd.U32x4, Simd.shuffle(Simd.load(input + 48), ReverseBytes))

            abcd = Swag.vecSha1Rounds4(abcd, e + w0, 0)
            advance'0(w1, &abcd, &previous)
            advance'0(w2, &abcd, &previous)
            advance'0(w3, &abcd, &previous)
            w0 = extend(w0, w1, w2, w3)
            advance'0(w0, &abcd, &previous)

            w1 = extend(w1, w2, w3, w0)
            advance'1(w1, &abcd, &previous)
            w2 = extend(w2, w3, w0, w1)
            advance'1(w2, &abcd, &previous)
            w3 = extend(w3, w0, w1, w2)
            advance'1(w3, &abcd, &previous)
            w0 = extend(w0, w1, w2, w3)
            advance'1(w0, &abcd, &previous)
            w1 = extend(w1, w2, w3, w0)
            advance'1(w1, &abcd, &previous)

            w2 = extend(w2, w3, w0, w1)
            advance'2(w2, &abcd, &previous)
            w3 = extend(w3, w0, w1, w2)
            advance'2(w3, &abcd, &previous)
            w0 = extend(w0, w1, w2, w3)
            advance'2(w0, &abcd, &previous)
            w1 = extend(w1, w2, w3, w0)
            advance'2(w1, &abcd, &previous)
            w2 = extend(w2, w3, w0, w1)
            advance'2(w2, &abcd, &previous)

            w3 = extend(w3, w0, w1, w2)
            advance'3(w3, &abcd, &previous)
            w0 = extend(w0, w1, w2, w3)
            advance'3(w0, &abcd, &previous)
            w1 = extend(w1, w2, w3, w0)
            advance'3(w1, &abcd, &previous)
            w2 = extend(w2, w3, w0, w1)
            advance'3(w2, &abcd, &previous)
            w3 = extend(w3, w0, w1, w2)
            advance'3(w3, &abcd, &previous)

            e     = Swag.vecSha1NextE(previous, e)
            abcd  += savedAbcd
            input += 64
        }

        Simd.store(.state.buffer, Simd.permute(abcd, ReverseWords))
        .state[4] = e[3]
    }

    mtd transformPortable(buf: const [*] u8)
    {
        var w: [80] u32

        let input = cast(const [*] u32, buf)
        for index in 16 do
            w[index] = Math.bigEndianToNative(input[index])

        var i = 16'u32
        while i < 80
        {
            w[i] = Swag.rol(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1)
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

            let temp = Swag.rol(a, 5) + f + e + k + w[i]
            e = d
            d = c
            c = Swag.rol(b, 30)
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
            .transformBlocks(.data, 1)
            used = 0
        }

        Swag.memset(.data.buffer + used, 0, 56 - used)
        cast([*] u64, .data.buffer)[7] = Math.nativeToBigEndian(.bitLength)
        .transformBlocks(.data, 1)
        return .state
    }

    // Resets the sequence to the standard SHA-1 initial state.
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

            .transformBlocks(.data, 1)
            .bitLength  += 512
            .dataLength = 0
            input       += copied
            remaining   -= copied
        }

        let blocks = remaining / 64
        if blocks
        {
            .transformBlocks(input, blocks)
            let processed = blocks * 64
            .bitLength += processed * 8
            input      += processed
            remaining  -= processed
        }

        if remaining
        {
            Swag.memcpy(.data.buffer, input, remaining)
            .dataLength = cast(u32, remaining)
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
