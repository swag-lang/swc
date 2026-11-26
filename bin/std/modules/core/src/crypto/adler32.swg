// https://tools.ietf.org/html/rfc1950#section-9
// https://github.com/madler/zlib/blob/master/adler32.c

#global namespace Hash

using Core.Math

#[Swag.Inline]
private func adlerWeights(bytes: Simd.U8x16, weights: Simd.S8x16)->Simd.S32x4
{
    return Simd.mulAddPairs(Simd.mulAddPairs(bytes, weights), Simd.splat(1's16))
}

private const AdlerWeights16 = cast(Simd.S8x16, [16's8, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1])

#[Swag.Inline]
private func updateAdlerBlock16(input: const [*] u8, byteSum, weightedSum: *u32)
{
    let bytes = Simd.load(input)
    weightedSum[] += 16 * byteSum[] + cast(u32, Simd.sum(adlerWeights(bytes, AdlerWeights16)))
    byteSum[]     += Simd.sumWide(bytes)
}

private func updateAdlerBlocks64(input: const [*] u8, count: u64, byteSum, weightedSum: *u32)
{
    // A pair's weight is at most 64 + 63, so its byte multiply-add cannot saturate.
    const Weights64 = cast(Simd.S8x16, [64's8, 63, 62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 51, 50, 49])
    const Weights48 = cast(Simd.S8x16, [48's8, 47, 46, 45, 44, 43, 42, 41, 40, 39, 38, 37, 36, 35, 34, 33])
    const Weights32 = cast(Simd.S8x16, [32's8, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17])
    let zero = Simd.splat(0'u8)
    var sum, prefixes: Simd.U64x2
    var weighted:      Simd.S32x4

    // Keep block sums and their prefixes packed until the end of the reduction period.
    for block in count
    {
        let bytes  = input + block * 64
        let first  = Simd.load(bytes)
        let second = Simd.load(bytes + 16)
        let third  = Simd.load(bytes + 32)
        let fourth = Simd.load(bytes + 48)

        prefixes += sum
        sum      += Simd.absoluteDifferences(first, zero) + Simd.absoluteDifferences(second, zero) +
                    Simd.absoluteDifferences(third, zero) + Simd.absoluteDifferences(fourth, zero)
        weighted += adlerWeights(first, Weights64) + adlerWeights(second, Weights48) +
                    adlerWeights(third, Weights32) + adlerWeights(fourth, AdlerWeights16)
    }

    weightedSum[] += 64 * (cast(u32, count) * byteSum[] + cast(u32, Simd.sum(prefixes))) +
                     cast(u32, Simd.sum(weighted))
    byteSum[] += cast(u32, Simd.sum(sum))
}

// Computes an Adler-32 checksum incrementally.
public struct Adler32
{
    internal currentValue: u32 = 1
}

private impl Adler32
{
    const Modulus = 65521

    #[Swag.NoInline]
    mtd updateLarge(input: const [*] u8, byteCount: u64)
    {
        // Round the worst-case modulo interval down to a whole SIMD block.
        const BlocksPerReduction = 5552 / 64
        var byteSum     = .currentValue & 0xFFFF
        var weightedSum = .currentValue >> 16
        var offset      = 0'u64

        while byteCount - offset >= 64
        {
            let blocks = Swag.min((byteCount - offset) / 64, BlocksPerReduction)
            updateAdlerBlocks64(input + offset, blocks, &byteSum, &weightedSum)
            offset      += blocks * 64
            byteSum     %= Modulus
            weightedSum %= Modulus
        }

        if offset < byteCount
        {
            while byteCount - offset >= 16
            {
                updateAdlerBlock16(input + offset, &byteSum, &weightedSum)
                offset += 16
            }

            for index in offset until byteCount
            {
                byteSum     += input[index]
                weightedSum += byteSum
            }

            byteSum     %= Modulus
            weightedSum %= Modulus
        }

        .currentValue = byteSum | (weightedSum << 16)
    }
}

public impl Adler32
{
    // Resets the checksum to its initial Adler-32 value.
    mtd reset()
    {
        Swag.init(me, 1)
    }

    // Includes `buffer` in the running checksum.
    mtd update(buffer: const [..] u8)
    {
        var byteSum     = .currentValue & 0xFFFF
        var weightedSum = (.currentValue >> 16) & 0xFFFF

        let byteCount = buffer.count
        if not byteCount do
            return

        let input = buffer.buffer
        if byteCount == 1
        {
            byteSum += input[0]
            if byteSum >= Modulus do
                byteSum -= Modulus
            weightedSum += byteSum
            if weightedSum >= Modulus do
                weightedSum -= Modulus
        }
        elif byteCount < 16
        {
            for byte in buffer
            {
                byteSum     += byte
                weightedSum += byteSum
            }

            if byteSum >= Modulus do
                byteSum -= Modulus
            weightedSum %= Modulus
        }
        else
        {
            if byteCount >= 128
            {
                .updateLarge(input, byteCount)
                return
            }

            updateAdlerBlock16(input, &byteSum, &weightedSum)
            var offset = 16'u64
            while byteCount - offset >= 16
            {
                updateAdlerBlock16(input + offset, &byteSum, &weightedSum)
                offset += 16
            }

            for index in offset until byteCount
            {
                byteSum     += input[index]
                weightedSum += byteSum
            }

            byteSum     %= Modulus
            weightedSum %= Modulus
        }

        .currentValue = byteSum | (weightedSum << 16)
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes the Adler-32 checksum of `buffer` in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8)->u32
    {
        var checksum: Adler32
        checksum.reset()
        checksum.update(buffer)
        return checksum.value()
    }
}
