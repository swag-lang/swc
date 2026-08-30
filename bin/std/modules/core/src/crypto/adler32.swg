// https://tools.ietf.org/html/rfc1950#section-9
// https://github.com/madler/zlib/blob/master/adler32.c

#global namespace Hash

#[Swag.Inline]
private func updateAdlerBlock16(input: const [*] u8, s1, s2: *u32)
{
    let bytes       = Math.Simd.load(input)
    let low         = cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(bytes)
    let high        = cast #bit(Math.Simd.S16x8) Math.Simd.widenHigh(bytes)
    let ones        = Math.Simd.splat(1's16)
    let weightsLow  = cast(Math.Simd.S16x8) [16's16, 15, 14, 13, 12, 11, 10, 9]
    let weightsHigh = cast(Math.Simd.S16x8) [8's16, 7, 6, 5, 4, 3, 2, 1]
    let sums        = Math.Simd.mulAddPairs(low, ones) + Math.Simd.mulAddPairs(high, ones)
    let weighted    = Math.Simd.mulAddPairs(low, weightsLow) + Math.Simd.mulAddPairs(high, weightsHigh)
    let sum         = cast(u32) Math.Simd.sum(sums)
    let weightedSum = cast(u32) Math.Simd.sum(weighted)
    s2[] += 16 * s1[] + weightedSum
    s1[] += sum
}

// Computes an Adler-32 checksum incrementally.
public struct Adler32
{
    internal currentValue: u32 = 1
}

public impl Adler32
{
    private const Base = 65521
    private const NMax = 5552

    // Resets the checksum to its initial Adler-32 value.
    mtd reset()
    {
        Swag.init(me, 1)
    }

    // Includes `buffer` in the running checksum.
    mtd update(buffer: const [..] u8)
    {
        var s1 = .currentValue & 0xFFFF
        var s2 = (.currentValue >> 16) & 0xFFFF

        let countof = buffer.count
        if !countof do
            return

        let input = buffer.buffer
        if countof == 1
        {
            s1 += input[0]
            if s1 >= Base do
                s1 -= Base
            s2 += s1
            if s2 >= Base do
                s2 -= Base
        }
        elif countof < 16
        {
            for b in buffer
            {
                s1 += b
                s2 += s1
            }

            if s1 >= Base do
                s1 -= Base
            s2 %= Base
        }
        else
        {
            const n = NMax / 16
            var i = 0'u64

            while i + NMax <= countof
            {
                for rounds in n
                {
                    updateAdlerBlock16(input + i, &s1, &s2)
                    i += 16
                }

                s1 %= Base
                s2 %= Base
            }

            if i < countof
            {
                while i + 16 <= countof
                {
                    updateAdlerBlock16(input + i, &s1, &s2)
                    i += 16
                }

                while i < countof
                {
                    s1 += input[i]
                    s2 += s1
                    i  += 1
                }

                s1 %= Base
                s2 %= Base
            }
        }

        .currentValue = s1 | (s2 << 16)
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes the Adler-32 checksum of `buffer` in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8)->u32
    {
        var v: Adler32
        v.reset()
        v.update(buffer)
        return v.value()
    }
}
