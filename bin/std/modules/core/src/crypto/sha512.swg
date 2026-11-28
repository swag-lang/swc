#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

// Size in bytes of one SHA-384 or SHA-512 input block.
public const Sha512BlockSize = 128

// SHA-512 digest size in bytes.
public const Sha512DigestSize = 64

// SHA-384 digest size in bytes.
public const Sha384DigestSize = 48

// SHA-512/224 digest size in bytes.
public const Sha512_224DigestSize = 28

// SHA-512/256 digest size in bytes.
public const Sha512_256DigestSize = 32

private const Sha512Constants: [80] u64 = [
    0x428A2F98D728AE22, 0x7137449123EF65CD, 0xB5C0FBCFEC4D3B2F, 0xE9B5DBA58189DBBC,
    0x3956C25BF348B538, 0x59F111F1B605D019, 0x923F82A4AF194F9B, 0xAB1C5ED5DA6D8118,
    0xD807AA98A3030242, 0x12835B0145706FBE, 0x243185BE4EE4B28C, 0x550C7DC3D5FFB4E2,
    0x72BE5D74F27B896F, 0x80DEB1FE3B1696B1, 0x9BDC06A725C71235, 0xC19BF174CF692694,
    0xE49B69C19EF14AD2, 0xEFBE4786384F25E3, 0x0FC19DC68B8CD5B5, 0x240CA1CC77AC9C65,
    0x2DE92C6F592B0275, 0x4A7484AA6EA6E483, 0x5CB0A9DCBD41FBD4, 0x76F988DA831153B5,
    0x983E5152EE66DFAB, 0xA831C66D2DB43210, 0xB00327C898FB213F, 0xBF597FC7BEEF0EE4,
    0xC6E00BF33DA88FC2, 0xD5A79147930AA725, 0x06CA6351E003826F, 0x142929670A0E6E70,
    0x27B70A8546D22FFC, 0x2E1B21385C26C926, 0x4D2C6DFC5AC42AED, 0x53380D139D95B3DF,
    0x650A73548BAF63DE, 0x766A0ABB3C77B2A8, 0x81C2C92E47EDAEE6, 0x92722C851482353B,
    0xA2BFE8A14CF10364, 0xA81A664BBC423001, 0xC24B8B70D0F89791, 0xC76C51A30654BE30,
    0xD192E819D6EF5218, 0xD69906245565A910, 0xF40E35855771202A, 0x106AA07032BBD1B8,
    0x19A4C116B8D2D0C8, 0x1E376C085141AB53, 0x2748774CDF8EEB99, 0x34B0BCB5E19B48A8,
    0x391C0CB3C5C95A63, 0x4ED8AA4AE3418ACB, 0x5B9CCA4F7763E373, 0x682E6FF3D6B2B8A3,
    0x748F82EE5DEFB2FC, 0x78A5636F43172F60, 0x84C87814A1F0AB72, 0x8CC702081A6439EC,
    0x90BEFFFA23631E28, 0xA4506CEBDE82BDE9, 0xBEF9A3F7B2C67915, 0xC67178F2E372532B,
    0xCA273ECEEA26619C, 0xD186B8C721C0C207, 0xEADA7DD6CDE0EB1E, 0xF57D4F7FEE6ED178,
    0x06F067AA72176FBA, 0x0A637DC5A2C898A6, 0x113F9804BEF90DAE, 0x1B710B35131C471B,
    0x28DB77F523047D84, 0x32CAAB7B40C72493, 0x3C9EBE0A15C9BEBC, 0x431D67C49C100D4C,
    0x4CC5D4BECB3E42B6, 0x597F299CFC657E2A, 0x5FCB6FAB3AD6FAEC, 0x6C44198C4A475817]

// Retaining one schedule window keeps the dependencies close to each round.
private const Sha512ScheduleWords = 16

#[Swag.Inline]
private func loadSha512SchedulePair(schedule: [*] u64, index: u64)->Math.Simd.U64x2
{
    return Math.Simd.load(schedule + (index & (Sha512ScheduleWords - 1)))
}

// Both words depend on earlier pairs, so they can share the packed rotations.
#[Swag.Inline]
private func sha512ExtendPair(schedule: [*] u64, index: u64)->Math.Simd.U64x2
{
    using Math

    let x        = loadSha512SchedulePair(schedule, index - 15)
    let y        = loadSha512SchedulePair(schedule, index - 2)
    let sigma0   = Swag.ror(x, 1_u8) ^ Swag.ror(x, 8_u8) ^ (x >> 7)
    let sigma1   = Swag.ror(y, 19_u8) ^ Swag.ror(y, 61_u8) ^ (y >> 6)
    let expanded = loadSha512SchedulePair(schedule, index - 16) + sigma0 + loadSha512SchedulePair(schedule, index - 7) + sigma1
    let offset = index & (Sha512ScheduleWords - 1)

    Simd.store(schedule + offset, expanded)
    Simd.store(schedule + offset + Sha512ScheduleWords, expanded)
    return expanded
}

#[Swag.Inline]
private func(Extend: bool) sha512SchedulePair(index: u64, schedule: [*] u64)->Math.Simd.U64x2
{
    using Math

    let constants = Simd.load(Sha512Constants.buffer + index)
    #static if Extend
    {
        return constants + sha512ExtendPair(schedule, index)
    }
    else
    {
        return constants + Simd.load(schedule + index)
    }
}

#[Swag.Inline]
private func sha512RoundFirst(e, f, g, h, scheduled: u64)->u64
{
    let sum    = Swag.ror(e, 14_u8) ^ Swag.ror(e, 18_u8) ^ Swag.ror(e, 41_u8)
    let choice = (e & f) ^ (~e & g)
    return h + sum + choice + scheduled
}

#[Swag.Inline]
private func sha512RoundSecond(a, b, c: u64)->u64
{
    let sum      = Swag.ror(a, 28_u8) ^ Swag.ror(a, 34_u8) ^ Swag.ror(a, 39_u8)
    let majority = (a & b) ^ (a & c) ^ (b & c)
    return sum + majority
}

private struct Sha512Core
{
    data:          [Sha512BlockSize] u8
    state:         [8] u64
    dataLength:    u64
    bitLengthLow:  u64
    bitLengthHigh: u64
    digestSize:    u64
}

impl Sha512Core
{
    mtd reset(digestSize: u64, variant: u32)
    {
        Swag.init(me, 1)
        .digestSize = digestSize
        if variant == 1
        {
            .state = [
                0xCBBB9D5DC1059ED8, 0x629A292A367CD507, 0x9159015A3070DD17, 0x152FECD8F70E5939,
                0x67332667FFC00B31, 0x8EB44A8768581511, 0xDB0C2E0D64F98FA7, 0x47B5481DBEFA4FA4]
        }
        else if variant == 2
        {
            .state = [
                0x8C3D37C819544DA2, 0x73E1996689DCD4D6, 0x1DFAB7AE32FF9C82, 0x679DD514582F9FCF,
                0x0F6D2B697BD44DA8, 0x77E36F7304C48942, 0x3F9D85A86A1D36C8, 0x1112E6AD91D692A1]
        }
        else if variant == 3
        {
            .state = [
                0x22312194FC2BF72C, 0x9F555FA3C84C64C2, 0x2393B86B6F53B151, 0x963877195940EABD,
                0x96283EE2A88EFFE3, 0xBE5E1E2553863992, 0x2B0199FC2C85B8AA, 0x0EB72DDC81C52CA2]
        }
        else
        {
            .state = [
                0x6A09E667F3BCC908, 0xBB67AE8584CAA73B, 0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1,
                0x510E527FADE682D1, 0x9B05688C2B3E6C1F, 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179]
        }
    }

    mtd update(data: const [..] u8)
    {
        var remaining = data.count
        if remaining == 0
        {
            return
        }

        var input = data.buffer

        if .dataLength
        {
            let copied = Math.min(remaining, Sha512BlockSize - .dataLength)
            Swag.memcpy(.data.buffer + .dataLength, input, copied)
            .dataLength += copied
            if .dataLength < Sha512BlockSize
            {
                return
            }

            .transformBlocks(.data)
            .dataLength = 0
            input       += copied
            remaining   -= copied
        }

        let blocks = remaining / Sha512BlockSize
        if blocks
        {
            .transformBlocks(input, blocks)
            let consumed = blocks * Sha512BlockSize
            input     += consumed
            remaining -= consumed
        }

        if remaining
        {
            Swag.memcpy(.data.buffer, input, remaining)
            .dataLength = remaining
        }
    }

    mtd clear()
    {
        Crypto.secureClear(.data)
        Crypto.secureClear(.state)
        .dataLength    = 0
        .bitLengthLow  = 0
        .bitLengthHigh = 0
        .digestSize    = 0
    }

    mtd finalize()->[8] u64
    {
        .finalizeBlocks()
        return .state
    }

    // A fresh context leaves its block zero-initialized.
    #[Swag.Inline]
    mtd computeFresh(data: const [..] u8)
    {
        if data.count < 112
        {
            if data.count
            {
                Swag.memcpy(.data.buffer, data.buffer, data.count)
            }

            .data[data.count] = 0x80
            let lowLength = cast([*] u64, .data.buffer + 120)
            lowLength[0] = Math.nativeToBigEndian(data.count * 8)
            .transformBlocks(.data)
        }
        else
        {
            let blocks = data.count / Sha512BlockSize
            if blocks
            {
                .transformBlocks(data.buffer, blocks)
            }

            let consumed = blocks * Sha512BlockSize
            .dataLength = data.count - consumed
            if .dataLength
            {
                Swag.memcpy(.data.buffer, data.buffer + consumed, .dataLength)
            }
            .finalizeBlocks()
        }
    }

    #[Swag.Inline]
    mtd finalizeBlocks()
    {
        let oldLow = .bitLengthLow
        .bitLengthLow += .dataLength * 8
        if .bitLengthLow < oldLow
        {
            .bitLengthHigh += 1
        }

        let finalLow  = .bitLengthLow
        let finalHigh = .bitLengthHigh

        .data[.dataLength] = 0x80
        .dataLength        += 1
        if .dataLength > 112
        {
            Swag.memset(.data.buffer + .dataLength, 0, Sha512BlockSize - .dataLength)
            .transformBlocks(.data)
            .dataLength = 0
        }

        Swag.memset(.data.buffer + .dataLength, 0, 112 - .dataLength)
        let lengthWords = cast([*] u64, .data.buffer + 112)
        lengthWords[0] = Math.nativeToBigEndian(finalHigh)
        lengthWords[1] = Math.nativeToBigEndian(finalLow)
        .transformBlocks(.data)
        .dataLength = 0
    }

    // The keyed prefix occupies one block and the outer input is one digest.
    mtd(DigestWords: u64) finishHmacOuter(digest: const [*] u64)->const [*] u64
    {
        const DigestSize   = DigestWords * #sizeof(u64)
        const LengthOffset = 112
        const BitLength    = (Sha512BlockSize + DigestSize) * 8
        Crypto.writeSha512HmacDigest!{DigestWords}(digest, .data.buffer)
        .data[DigestSize] = 0x80
        Swag.memset(.data.buffer + DigestSize + 1, 0, LengthOffset - DigestSize - 1)
        let lengthWords = cast([*] u64, .data.buffer + LengthOffset)
        lengthWords[0] = 0
        lengthWords[1] = Math.nativeToBigEndian(BitLength)
        .transformBlocks(.data)
        return .state.buffer
    }

    private mtd transformBlocks(buf: const [*] u8, blockCount = 1_u64)
    {
        using Math
        // Mirror the window so an odd pair spanning its boundary stays contiguous.
        var words: [Sha512ScheduleWords * 2] u64
        let schedule = words.buffer
        for block in blockCount
        {
            let input = cast(const [*] u64, buf + block * Sha512BlockSize)
            for pair in Sha512ScheduleWords / 2
            {
                let index = pair * 2
                let converted = Math.bigEndianToNative(Simd.load(input + index))
                Simd.store(schedule + index, converted)
                Simd.store(schedule + index + Sha512ScheduleWords, converted)
            }

            var a = .state[0]
            var b = .state[1]
            var c = .state[2]
            var d = .state[3]
            var e = .state[4]
            var f = .state[5]
            var g = .state[6]
            var h = .state[7]

            // Rotate the roles of the locals through all eight positions.
            #[Swag.Mixin]
            func(Index: u64, Extend: bool) compressGroup()
            {
                scope
                {
                    let pair0 = sha512SchedulePair!{Extend}(Index, schedule)
                    let first0 = sha512RoundFirst(e, f, g, h, pair0[0])
                    d += first0
                    h = first0 + sha512RoundSecond(a, b, c)
                    let first1 = sha512RoundFirst(d, e, f, g, pair0[1])
                    c += first1
                    g = first1 + sha512RoundSecond(h, a, b)

                    let pair1 = sha512SchedulePair!{Extend}(Index + 2, schedule)
                    let first2 = sha512RoundFirst(c, d, e, f, pair1[0])
                    b += first2
                    f = first2 + sha512RoundSecond(g, h, a)
                    let first3 = sha512RoundFirst(b, c, d, e, pair1[1])
                    a += first3
                    e = first3 + sha512RoundSecond(f, g, h)

                    let pair2 = sha512SchedulePair!{Extend}(Index + 4, schedule)
                    let first4 = sha512RoundFirst(a, b, c, d, pair2[0])
                    h += first4
                    d = first4 + sha512RoundSecond(e, f, g)
                    let first5 = sha512RoundFirst(h, a, b, c, pair2[1])
                    g += first5
                    c = first5 + sha512RoundSecond(d, e, f)

                    let pair3 = sha512SchedulePair!{Extend}(Index + 6, schedule)
                    let first6 = sha512RoundFirst(g, h, a, b, pair3[0])
                    f += first6
                    b = first6 + sha512RoundSecond(c, d, e)
                    let first7 = sha512RoundFirst(f, g, h, a, pair3[1])
                    e += first7
                    a = first7 + sha512RoundSecond(b, c, d)
                }
            }

            compressGroup!{0, false}()
            compressGroup!{8, false}()
            compressGroup!{16, true}()
            compressGroup!{24, true}()
            compressGroup!{32, true}()
            compressGroup!{40, true}()
            compressGroup!{48, true}()
            compressGroup!{56, true}()
            compressGroup!{64, true}()
            compressGroup!{72, true}()

            .state[0]     += a
            .state[1]     += b
            .state[2]     += c
            .state[3]     += d
            .state[4]     += e
            .state[5]     += f
            .state[6]     += g
            .state[7]     += h
            .bitLengthLow += Sha512BlockSize * 8
            if .bitLengthLow < Sha512BlockSize * 8
            {
                .bitLengthHigh += 1
            }
        }
    }
}

#[Swag.Inline]
private func(Words: u64) truncateSha512Digest(state: const [*] u64)->[Words] u64
{
    var digest: #returntype
    for index in Words
    {
        digest[index] = state[index]
    }

    return digest
}

#[Swag.Inline]
private func truncateSha512_224Digest(state: const [*] u64)->[7] u32
{
    var digest: #returntype
    for index in digest.count
    {
        let shift = (index & 1) == 0 ? 32 : 0
        digest[index] = cast(u32, state[index / 2] >> shift)
    }

    return digest
}

// Computes a SHA-512 digest incrementally.
public struct Sha512
{
    private core: Sha512Core
}

impl Sha512
{
    #[Swag.Inline]
    mtd finishHmacInner()->const [*] u64
    {
        .core.finalizeBlocks()
        return .core.state.buffer
    }

    #[Swag.Inline]
    mtd finishHmacOuter(digest: const [*] u64)->const [*] u64 => .core.finishHmacOuter!{8}(digest)

    #[Swag.Inline]
    mtd const hmacPrefixState()->const *[8] u64 => &.core.state

    #[Swag.Inline]
    mtd compressHmacDigestBlock(prefix: const *[8] u64, block: const [*] u8)->const [*] u64
    {
        .core.state = prefix[]
        .core.transformBlocks(block)
        return .core.state.buffer
    }
}

public impl Sha512
{
    // Stores SHA-512 output as eight 64-bit words in digest order.
    alias Digest = [8] u64

    // Resets the sequence to the standard SHA-512 initial state.
    mtd reset() => .core.reset(Sha512DigestSize, 0)

    // Includes `data` in the running digest.
    mtd update(data: const [..] u8)
    {
        if not .core.digestSize
        {
            .reset()
        }

        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 512-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize
        {
            .reset()
        }

        return .core.finalize()
    }

    // Computes the SHA-512 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha512
        hash.reset()
        hash.core.computeFresh(data)
        return hash.core.state
    }
}

// Computes a SHA-384 digest incrementally.
public struct Sha384
{
    private core: Sha512Core
}

impl Sha384
{
    #[Swag.Inline]
    mtd finishHmacInner()->const [*] u64
    {
        .core.finalizeBlocks()
        return .core.state.buffer
    }

    #[Swag.Inline]
    mtd finishHmacOuter(digest: const [*] u64)->const [*] u64 => .core.finishHmacOuter!{6}(digest)

    #[Swag.Inline]
    mtd const hmacPrefixState()->const *[8] u64 => &.core.state
}

public impl Sha384
{
    // Stores SHA-384 output as six 64-bit words in digest order.
    alias Digest = [6] u64

    // Resets the sequence to the standard SHA-384 initial state.
    mtd reset() => .core.reset(Sha384DigestSize, 1)

    // Includes `data` in the running digest.
    mtd update(data: const [..] u8)
    {
        if not .core.digestSize
        {
            .reset()
        }

        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 384-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize
        {
            .reset()
        }

        .core.finalizeBlocks()
        return truncateSha512Digest!{6}(.core.state.buffer)
    }

    // Computes the SHA-384 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha384
        hash.reset()
        hash.core.computeFresh(data)
        return truncateSha512Digest!{6}(hash.core.state.buffer)
    }
}

// Computes a SHA-512/224 digest incrementally.
public struct Sha512_224
{
    private core: Sha512Core
}

public impl Sha512_224
{
    // Stores SHA-512/224 output as seven 32-bit words in digest order.
    alias Digest = [7] u32

    // Resets the sequence to the SHA-512/224 initial state.
    mtd reset() => .core.reset(Sha512_224DigestSize, 2)

    // Includes `data` in the running digest.
    mtd update(data: const [..] u8)
    {
        if not .core.digestSize
        {
            .reset()
        }

        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 224-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize
        {
            .reset()
        }

        .core.finalizeBlocks()
        return truncateSha512_224Digest(.core.state.buffer)
    }

    // Computes the SHA-512/224 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha512_224
        hash.reset()
        hash.core.computeFresh(data)
        return truncateSha512_224Digest(hash.core.state.buffer)
    }
}

// Computes a SHA-512/256 digest incrementally.
public struct Sha512_256
{
    private core: Sha512Core
}

public impl Sha512_256
{
    // Stores SHA-512/256 output as four 64-bit words in digest order.
    alias Digest = [4] u64

    // Resets the sequence to the SHA-512/256 initial state.
    mtd reset() => .core.reset(Sha512_256DigestSize, 3)

    // Includes `data` in the running digest.
    mtd update(data: const [..] u8)
    {
        if not .core.digestSize
        {
            .reset()
        }

        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 256-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize
        {
            .reset()
        }

        .core.finalizeBlocks()
        return truncateSha512Digest!{4}(.core.state.buffer)
    }

    // Computes the SHA-512/256 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha512_256
        hash.reset()
        hash.core.computeFresh(data)
        return truncateSha512Digest!{4}(hash.core.state.buffer)
    }
}
