// https://tools.ietf.org/html/rfc1950#section-9
// https://github.com/madler/zlib/blob/master/adler32.c

#global namespace Hash

using Core.Math

#[Swag.Inline]
private func updateAdlerBlock16(input: const [*] u8, byteSum, weightedSum: *u32)
{
    let bytes = Simd.load(input)
    let low   = cast #bit(Simd.S16x8, Simd.widenLow(bytes))
    let high  = cast #bit(Simd.S16x8, Simd.widenHigh(bytes))

    let ones        = Simd.splat(1's16)
    let weightsLow  = cast(Simd.S16x8, [16's16, 15, 14, 13, 12, 11, 10, 9])
    let weightsHigh = cast(Simd.S16x8, [8's16, 7, 6, 5, 4, 3, 2, 1])

    let sums             = Simd.mulAddPairs(low, ones) + Simd.mulAddPairs(high, ones)
    let weighted         = Simd.mulAddPairs(low, weightsLow) + Simd.mulAddPairs(high, weightsHigh)
    let blockSum         = cast(u32, Simd.sum(sums))
    let blockWeightedSum = cast(u32, Simd.sum(weighted))

    weightedSum[] += 16 * byteSum[] + blockWeightedSum
    byteSum[]     += blockSum
}

// Computes an Adler-32 checksum incrementally.
public struct Adler32
{
    internal currentValue: u32 = 1
}

public impl Adler32
{
    private const Modulus = 65521
    private const BytesPerReduction = 5552

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
            const BlocksPerReduction = BytesPerReduction / 16
            var byteOffset = 0'u64

            // Reduce both sums before their accumulated values can overflow.
            while byteOffset + BytesPerReduction <= byteCount
            {
                for BlocksPerReduction
                {
                    updateAdlerBlock16(input + byteOffset, &byteSum, &weightedSum)
                    byteOffset += 16
                }

                byteSum     %= Modulus
                weightedSum %= Modulus
            }

            // Finish the partial reduction block, including its scalar tail.
            if byteOffset < byteCount
            {
                while byteOffset + 16 <= byteCount
                {
                    updateAdlerBlock16(input + byteOffset, &byteSum, &weightedSum)
                    byteOffset += 16
                }

                while byteOffset < byteCount
                {
                    byteSum     += input[byteOffset]
                    weightedSum += byteSum
                    byteOffset  += 1
                }

                byteSum     %= Modulus
                weightedSum %= Modulus
            }
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
