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
    // Center the byte weights so four partial pair sums fit in signed 16 bits.
    const Weights32 = cast(Simd.S8x16, [32's8, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17])
    const Weights0 = cast(Simd.S8x16, [0's8, -1, -2, -3, -4, -5, -6, -7, -8, -9, -10, -11, -12, -13, -14, -15])
    const WeightsMinus16 = cast(Simd.S8x16, [-16's8, -17, -18, -19, -20, -21, -22, -23, -24, -25, -26, -27, -28, -29, -30, -31])
    let zero = Simd.splat(0'u8)
    let ones = Simd.splat(1's16)
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
        // Each signed pair total lies between -22,950 and 23,970.
        let highPairs = Simd.mulAddPairs(first, Weights32) + Simd.mulAddPairs(second, AdlerWeights16)
        let lowPairs  = Simd.mulAddPairs(third, Weights0) + Simd.mulAddPairs(fourth, WeightsMinus16)
        weighted += Simd.mulAddPairs(highPairs + lowPairs, ones)
    }

    let blockBytes = cast(u32, Simd.sum(sum))
    // Restore the 32 removed from each byte's weight.
    let blockWeights = Simd.sum(weighted) + cast(s32, 32 * blockBytes)
    weightedSum[] += 64 * (cast(u32, count) * byteSum[] + cast(u32, Simd.sum(prefixes))) +
                     cast(u32, blockWeights)
    byteSum[] += blockBytes
}

#[Swag.Inline]
private func updateAdlerShort(input: const [*] u8, count: u64, byteSum, weightedSum: *u32)
{
    var sum      = byteSum[]
    var weighted = weightedSum[]
    var offset   = 0'u64
    while count - offset >= 4
    {
        let word   = Math.littleEndianToNative(cast(const [*] u32, input + offset)[0])
        let first  = word & 0xFF
        let second = (word >> 8) & 0xFF
        let third  = (word >> 16) & 0xFF
        let fourth = word >> 24
        // Each byte contributes to its own prefix and to the prefixes that follow.
        weighted += 4 * sum + 4 * first + 3 * second + 2 * third + fourth
        sum      += first + second + third + fourth
        offset   += 4
    }

    for index in offset until count
    {
        sum      += input[index]
        weighted += sum
    }

    byteSum[]     = sum
    weightedSum[] = weighted
}

// Computes an Adler-32 checksum incrementally.
public struct Adler32
{
    internal currentValue: u32 = 1
}

private impl Adler32
{
    const Modulus = 65521
    const TileBytes = 512 * 1024'u64
    const MaxTiles = 32

    func mergeTile(previous, tile: u32)->u32
    {
        // Tile checksums start from the Adler identity A = 1.
        const TileLength = cast(u32, TileBytes % Modulus)
        let prefixSum = ((previous & 0xFFFF) + Modulus - 1) % Modulus
        let byteSum = (prefixSum + (tile & 0xFFFF)) % Modulus
        let weightedSum = ((previous >> 16) + (tile >> 16) + TileLength * prefixSum) % Modulus
        return byteSum | (weightedSum << 16)
    }

    #[Swag.NoInline]
    mtd updateParallel(input: const [*] u8, byteCount: u64)
    {
        var checksum = .currentValue
        var offset = 0'u64
        var results: [MaxTiles] u32
        while byteCount - offset >= TileBytes
        {
            let tiles = Swag.min((byteCount - offset) / TileBytes, MaxTiles)
            let source = input + offset
            parallel for |source, &results| tile in tiles
            {
                var local: Adler32
                local.updateLarge(source + tile * TileBytes, TileBytes)
                results[tile] = local.currentValue
            }
            for tile in tiles do
                checksum = mergeTile(checksum, results[tile])
            offset += tiles * TileBytes
        }

        .currentValue = checksum
        if offset != byteCount do
            .updateLarge(input + offset, byteCount - offset)
    }

    #[Swag.NoInline]
    mtd updateLarge(input: const [*] u8, byteCount: u64)
    {
        if byteCount >= 4 * TileBytes and not Swag.jit() and Swag.workerCount() > 1
        {
            .updateParallel(input, byteCount)
            return
        }

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
        if not byteCount
        {
            return
        }

        let input = buffer.buffer
        if byteCount == 1
        {
            byteSum += input[0]
            if byteSum >= Modulus
            {
                byteSum -= Modulus
            }

            weightedSum += byteSum
            if weightedSum >= Modulus
            {
                weightedSum -= Modulus
            }
        }
        else if byteCount < 16
        {
            for byte in buffer
            {
                byteSum     += byte
                weightedSum += byteSum
            }

            if byteSum >= Modulus
            {
                byteSum -= Modulus
            }

            weightedSum %= Modulus
        }
        else
        {
            const BlocksPerReduction = BytesPerReduction / 16
            var byteOffset = 0_u64

            // Reduce both sums before their accumulated values can overflow.
            while byteCount - byteOffset >= BytesPerReduction
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
        let count = buffer.count
        if count == 0 do
            return 1

        let input = buffer.buffer
        if count >= 128
        {
            var checksum: Adler32
            checksum.updateLarge(input, count)
            return checksum.value()
        }

        var byteSum     = 1'u32
        var weightedSum = 0'u32
        var offset      = 0'u64
        while count - offset >= 16
        {
            updateAdlerBlock16(input + offset, &byteSum, &weightedSum)
            offset += 16
        }

        updateAdlerShort(input + offset, count - offset, &byteSum, &weightedSum)
        // The byte sum stays below the modulus for at most 127 bytes. The
        // weighted sum can reach the modulus when there are 23 bytes or more.
        if count > 22 do
            weightedSum %= Modulus
        return byteSum | (weightedSum << 16)
    }
}
