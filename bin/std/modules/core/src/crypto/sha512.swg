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
        elif variant == 2
        {
            .state = [
                0x8C3D37C819544DA2, 0x73E1996689DCD4D6, 0x1DFAB7AE32FF9C82, 0x679DD514582F9FCF,
                0x0F6D2B697BD44DA8, 0x77E36F7304C48942, 0x3F9D85A86A1D36C8, 0x1112E6AD91D692A1]
        }
        elif variant == 3
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
        if remaining == 0 do
            return
        var input = data.buffer

        if .dataLength
        {
            let copied = Math.min(remaining, Sha512BlockSize - .dataLength)
            Swag.memcpy(.data.buffer + .dataLength, input, copied)
            .dataLength += copied
            if .dataLength < Sha512BlockSize do
                return

            .transformBlock(.data)
            .dataLength = 0
            input       += copied
            remaining   -= copied
        }

        while remaining >= Sha512BlockSize
        {
            .transformBlock(input)
            input     += Sha512BlockSize
            remaining -= Sha512BlockSize
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
        var result: #returntype
        let oldLow = .bitLengthLow
        .bitLengthLow += .dataLength * 8
        if .bitLengthLow < oldLow do
            .bitLengthHigh += 1
        let finalLow  = .bitLengthLow
        let finalHigh = .bitLengthHigh

        .data[.dataLength] = 0x80
        .dataLength        += 1
        if .dataLength > 112
        {
            Swag.memset(.data.buffer + .dataLength, 0, Sha512BlockSize - .dataLength)
            .transformBlock(.data)
            .dataLength = 0
        }

        Swag.memset(.data.buffer + .dataLength, 0, 112 - .dataLength)
        let lengthWords = cast([*] u64, .data.buffer + 112)
        lengthWords[0] = Math.nativeToBigEndian(finalHigh)
        lengthWords[1] = Math.nativeToBigEndian(finalLow)
        .transformBlock(.data)
        .dataLength = 0
        result      = .state
        return result
    }

    private mtd transformBlock(buf: const [*] u8)
    {
        using Math
        var words: [80] u64
        let input    = cast(const [*] u64, buf)
        let schedule = words.buffer
        for pair in 8
        {
            let index = pair * 2
            Simd.store(schedule + index, Math.bigEndianToNative(Simd.load(input + index)))
        }

        // Both words depend on earlier pairs, so they can share the packed rotations.
        for pair in 8 until 40
        {
            let index    = pair * 2
            let x        = Simd.load(schedule + index - 15)
            let y        = Simd.load(schedule + index - 2)
            let sigma0   = Swag.ror(x, 1'u8) ^ Swag.ror(x, 8'u8) ^ (x >> 7)
            let sigma1   = Swag.ror(y, 19'u8) ^ Swag.ror(y, 61'u8) ^ (y >> 6)
            let expanded = Simd.load(schedule + index - 16) + sigma0 + Simd.load(schedule + index - 7) + sigma1
            Simd.store(schedule + index, expanded)
        }

        var a = .state[0]
        var b = .state[1]
        var c = .state[2]
        var d = .state[3]
        var e = .state[4]
        var f = .state[5]
        var g = .state[6]
        var h = .state[7]

        #[Swag.Inline]
        func round(a, b, c: u64, d: *u64, e, f, g: u64, h: *u64, scheduled: u64)
        {
            let sum1     = Swag.ror(e, 14'u8) ^ Swag.ror(e, 18'u8) ^ Swag.ror(e, 41'u8)
            let choice   = (e & f) ^ (~e & g)
            let temp1    = h[] + sum1 + choice + scheduled
            let sum0     = Swag.ror(a, 28'u8) ^ Swag.ror(a, 34'u8) ^ Swag.ror(a, 39'u8)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            d[] += temp1
            h[] = temp1 + sum0 + majority
        }

        // Rotate the roles of the local variables through all eight positions.
        for group in 10
        {
            let index = group * 8
            round(a, b, c, &d, e, f, g, &h, Sha512Constants[index] + words[index])
            round(h, a, b, &c, d, e, f, &g, Sha512Constants[index + 1] + words[index + 1])
            round(g, h, a, &b, c, d, e, &f, Sha512Constants[index + 2] + words[index + 2])
            round(f, g, h, &a, b, c, d, &e, Sha512Constants[index + 3] + words[index + 3])
            round(e, f, g, &h, a, b, c, &d, Sha512Constants[index + 4] + words[index + 4])
            round(d, e, f, &g, h, a, b, &c, Sha512Constants[index + 5] + words[index + 5])
            round(c, d, e, &f, g, h, a, &b, Sha512Constants[index + 6] + words[index + 6])
            round(b, c, d, &e, f, g, h, &a, Sha512Constants[index + 7] + words[index + 7])
        }

        .state[0]     += a
        .state[1]     += b
        .state[2]     += c
        .state[3]     += d
        .state[4]     += e
        .state[5]     += f
        .state[6]     += g
        .state[7]     += h
        .bitLengthLow += Sha512BlockSize * 8
        if .bitLengthLow < Sha512BlockSize * 8 do
            .bitLengthHigh += 1
    }
}

// Computes a SHA-512 digest incrementally.
public struct Sha512
{
    private core: Sha512Core
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
        if not .core.digestSize do
            .reset()
        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 512-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize do
            .reset()
        return .core.finalize()
    }

    // Computes the SHA-512 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha512
        hash.reset()
        hash.update(data)
        return hash.finalize()
    }
}

// Computes a SHA-384 digest incrementally.
public struct Sha384
{
    private core: Sha512Core
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
        if not .core.digestSize do
            .reset()
        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 384-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize do
            .reset()
        let state = .core.finalize()
        var result: #returntype
        for index in result.count do
            result[index] = state[index]
        return result
    }

    // Computes the SHA-384 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha384
        hash.reset()
        hash.update(data)
        return hash.finalize()
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
        if not .core.digestSize do
            .reset()
        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 224-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize do
            .reset()
        let fullDigest = .core.finalize()
        var result: #returntype
        for index in result.count
        {
            let shift = (index & 1) == 0 ? 32 : 0
            result[index] = cast(u32, fullDigest[index / 2] >> shift)
        }

        return result
    }

    // Computes the SHA-512/224 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha512_224
        hash.reset()
        hash.update(data)
        return hash.finalize()
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
        if not .core.digestSize do
            .reset()
        .core.update(data)
    }

    // Clears the current sequence state.
    mtd clear() => .core.clear()

    // Finalizes the current sequence and returns its 256-bit digest.
    mtd finalize()->Digest
    {
        if not .core.digestSize do
            .reset()
        let fullDigest = .core.finalize()
        var result: #returntype
        for index in result.count do
            result[index] = fullDigest[index]
        return result
    }

    // Computes the SHA-512/256 digest of `data` in one operation.
    func compute(data: const [..] u8)->Digest
    {
        var hash: Sha512_256
        hash.reset()
        hash.update(data)
        return hash.finalize()
    }
}
