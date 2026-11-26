#global namespace Hash

// Computes a CRC-32 checksum incrementally.
public struct Crc32
{
    internal currentValue: u32
}

private impl Crc32
{
    const LookupTable = #run buildLookupTable()

    func buildLookupTable()->[8, 256] u32
    {
        const Polynomial = 0xEDB8_8320'u32
        var table: #returntype
        for index in 256
        {
            var value = cast(u32, index)
            for 8 do
                value = value & 1 ? (value >> 1) ^ Polynomial : value >> 1
            table[0, index] = value
        }

        for slice in 1 until 8
        {
            for index in 256
            {
                let previous = table[slice - 1, index]
                table[slice, index] = (previous >> 8) ^ table[0, previous & 0xFF]
            }
        }

        return table
    }
}

private
{
    // Bit-reflected CRC-32 folding constants and Barrett polynomials, from "Fast CRC
    // Computation for Generic Polynomials Using PCLMULQDQ Instruction" (V. Gopal,
    // E. Ozturk, et al., 2009), as used by zlib's SSE4.2+PCLMUL path.
    // @LICENCE: Zlib
    // @ORIGIN: Chromium zlib, https://github.com/chromium/chromium/blob/main/third_party/zlib/crc32_simd.c
    // @MODIFIED: Ported to Swag vector intrinsics.
    // @NOTICE: /bin/THIRDPARTY.md#zlib
    const FoldK1K2 = cast(Math.Simd.U64x2, [0x0154442BD4'u64, 0x01C6E41596])
    const FoldK3K4 = cast(Math.Simd.U64x2, [0x01751997D0'u64, 0x00CCAA009E])
    const FoldK5   = cast(Math.Simd.U64x2, [0x0163CD6124'u64, 0x0000000000])
    const FoldPoly = cast(Math.Simd.U64x2, [0x01DB710641'u64, 0x01F7011641])
    const FoldZero = cast(Math.Simd.U64x2, [0'u64, 0])
    const FoldMask = cast(Math.Simd.U64x2, [0x0000_0000_FFFF_FFFF'u64, 0x0000_0000_FFFF_FFFF])

    // Folds 'length' bytes — at least 64, a multiple of 16 — into the running
    // inverted CRC-32 register with carry-less multiplications: four lanes of
    // sixty-four bytes in flight, folded down to one lane, then Barrett-reduced
    // back to thirty-two bits.
    func foldClmul(crcReg: u32, buffer: const [*] u8, length: u64)->u32
    {
        var seed: [2] u64 = [cast(u64, crcReg), 0]

        var buf = cast(const [*] u64, buffer)
        var len = length

        var x1 = Math.Simd.load(buf)
        var x2 = Math.Simd.load(buf + 2)
        var x3 = Math.Simd.load(buf + 4)
        var x4 = Math.Simd.load(buf + 6)

        x1 ^= Math.Simd.load(cast(const [*] u64, &seed[0]))

        var k = FoldK1K2
        buf += 8
        len -= 64

        while len >= 64
        {
            let x5 = Math.Simd.clmulLowLow(x1, k)
            let x6 = Math.Simd.clmulLowLow(x2, k)
            let x7 = Math.Simd.clmulLowLow(x3, k)
            let x8 = Math.Simd.clmulLowLow(x4, k)

            x1 = Math.Simd.clmulHighHigh(x1, k)
            x2 = Math.Simd.clmulHighHigh(x2, k)
            x3 = Math.Simd.clmulHighHigh(x3, k)
            x4 = Math.Simd.clmulHighHigh(x4, k)

            x1 ^= x5 ^ Math.Simd.load(buf)
            x2 ^= x6 ^ Math.Simd.load(buf + 2)
            x3 ^= x7 ^ Math.Simd.load(buf + 4)
            x4 ^= x8 ^ Math.Simd.load(buf + 6)

            buf += 8
            len -= 64
        }

        // Fold the four lanes into one.
        k = FoldK3K4
        var x5 = Math.Simd.clmulLowLow(x1, k)
        x1 = Math.Simd.clmulHighHigh(x1, k)
        x1 ^= x2 ^ x5
        x5 = Math.Simd.clmulLowLow(x1, k)
        x1 = Math.Simd.clmulHighHigh(x1, k)
        x1 ^= x3 ^ x5
        x5 = Math.Simd.clmulLowLow(x1, k)
        x1 = Math.Simd.clmulHighHigh(x1, k)
        x1 ^= x4 ^ x5

        while len >= 16
        {
            x5  = Math.Simd.clmulLowLow(x1, k)
            x1  = Math.Simd.clmulHighHigh(x1, k)
            x1  ^= Math.Simd.load(buf) ^ x5
            buf += 2
            len -= 16
        }

        // Fold 128 bits to 64, then Barrett-reduce to 32.
        var t = Math.Simd.clmulLowHigh(x1, k)
        x1 = Swag.vecAlign(x1, FoldZero, 8)
        x1 ^= t

        t  = Swag.vecAlign(x1, FoldZero, 4)
        x1 &= FoldMask
        x1 = Math.Simd.clmulLowLow(x1, FoldK5)
        x1 ^= t

        t  = x1 & FoldMask
        t  = Math.Simd.clmulLowHigh(t, FoldPoly)
        t  &= FoldMask
        t  = Math.Simd.clmulLowLow(t, FoldPoly)
        x1 ^= t

        var out: [2] u64
        Math.Simd.store(cast([*] u64, &out[0]), x1)
        return cast(u32, (out[0] >> 32))
    }
}

public impl Crc32
{
    // Resets the checksum to `seed`.
    //
    // `seed` is 0 to start a new sequence, or a previous checksum to continue it.
    mtd reset(seed: u32 = 0)
    {
        .currentValue = seed
    }

    // Includes `data` in the running checksum.
    mtd update(data: const [..] u8?)
    {
        var length = data.count
        if not length do
            return
        var current = unwrap data.buffer
        var cur     = ~.currentValue

        // Carry-less folding processes whole vectors. The slicing table handles short
        // messages and the remainder of a folded message.
        #static if not BIG_ENDIAN
        {
            if length >= 64 and Swag.hasCpuFeature(.CarrylessMultiply)
            {
                let folded = length & ~15'u64
                cur     = foldClmul(cur, current, folded)
                current += folded
                length  -= folded
            }
        }

        while length >= 8
        {
            let word  = Math.littleEndianToNative(cast(const [*] u64, current)[0])
            let mixed = word ^ cast(u64, cur)
            cur = LookupTable[7, mixed & 0xFF] ^
                  LookupTable[6, (mixed >> 8) & 0xFF] ^
                  LookupTable[5, (mixed >> 16) & 0xFF] ^
                  LookupTable[4, (mixed >> 24) & 0xFF] ^
                  LookupTable[3, (mixed >> 32) & 0xFF] ^
                  LookupTable[2, (mixed >> 40) & 0xFF] ^
                  LookupTable[1, (mixed >> 48) & 0xFF] ^
                  LookupTable[0, mixed >> 56]
            current += 8
            length  -= 8
        }

        for index in length do
            cur = (cur >> 8) ^ LookupTable[0, (cur & 0xFF) ^ current[index]]

        .currentValue = ~cur
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes the CRC-32 checksum of `buffer` in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8)->u32
    {
        var v: Crc32
        v.reset()
        v.update(buffer)
        return v.value()
    }
}
