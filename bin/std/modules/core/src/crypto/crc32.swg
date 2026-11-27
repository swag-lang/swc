#global namespace Hash

// Computes a CRC-32 checksum incrementally.
public struct Crc32
{
    internal currentValue: u32
}

private impl Crc32
{
    const LookupTable = #run buildLookupTable()

    #[Swag.Inline]
    func updateValue(data: const [..] u8?, previous: u32)->u32
    {
        var length = data.count
        if not length
        {
            return previous
        }

        var current = unwrap data.buffer
        var cur     = ~previous

        // Carry-less folding uses whole blocks and folds any partial final block
        // into the running vector. The slicing table handles shorter inputs.
        #static if not BIG_ENDIAN
        {
            if length >= 36 and Swag.hasCpuFeature(.CarrylessMultiply)
            {
                if length < 80
                {
                    return ~foldShort(cur, current, length)
                }

                return ~foldClmul(cur, current, length)
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

        if length == 0
        {
            return ~cur
        }

        if length & 4
        {
            let word  = Math.littleEndianToNative(cast(const [*] u32, current)[0])
            let mixed = cur ^ word
            cur = LookupTable[3, mixed & 0xFF] ^
                  LookupTable[2, (mixed >> 8) & 0xFF] ^
                  LookupTable[1, (mixed >> 16) & 0xFF] ^
                  LookupTable[0, mixed >> 24]
            current += 4
        }

        if length & 2
        {
            let word  = Math.littleEndianToNative(cast(const [*] u16, current)[0])
            let mixed = cur ^ cast(u32, word)
            cur     = (cur >> 16) ^ LookupTable[1, mixed & 0xFF] ^ LookupTable[0, (mixed >> 8) & 0xFF]
            current += 2
        }

        if length & 1
        {
            cur = (cur >> 8) ^ LookupTable[0, (cur & 0xFF) ^ current[0]]
        }

        return ~cur
    }

    func buildLookupTable()->[8, 256] u32
    {
        const Polynomial = 0xEDB8_8320_u32
        var table: #returntype
        for index in 256
        {
            var value = cast(u32, index)
            for 8
            {
                value = value & 1 ? (value >> 1) ^ Polynomial : value >> 1
            }

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
    // Bit-reflected CRC-32 folding constants from "Fast CRC
    // Computation for Generic Polynomials Using PCLMULQDQ Instruction" (V. Gopal,
    // E. Ozturk, et al., 2009), as used by zlib's SSE4.2+PCLMUL path.
    // @LICENCE: Zlib
    // @ORIGIN: Chromium zlib, https://github.com/chromium/chromium/blob/main/third_party/zlib/crc32_simd.c
    // @MODIFIED: Ported to Swag vector intrinsics.
    // @NOTICE: /bin/THIRDPARTY.md#zlib
    const FoldK1K2      = cast(Math.Simd.U64x2, [0x0154442BD4_u64, 0x01C6E41596])
    const FoldK3K4      = cast(Math.Simd.U64x2, [0x01751997D0_u64, 0x00CCAA009E])
    const FoldZero      = cast(Math.Simd.U64x2, [0_u64, 0])
    const CrcPolynomial = 0x04C1_1DB7_u32

    // The full-width Barrett reduction and fractional fold follow libdeflate's technique.
    // @LICENCE: MIT
    // @ORIGIN: libdeflate, https://github.com/ebiggers/libdeflate/blob/v1.26/lib/x86/crc32_pclmul_template.h
    // @MODIFIED: Derive constants and shuffle masks in Swag and use the existing vector API.
    // @NOTICE: /bin/THIRDPARTY.md#libdeflate
    const BarrettFactors = cast(Math.Simd.U64x2, [#run reflectedBarrettQuotient(),
                                                  (cast(u64, #run Math.reverse(CrcPolynomial)) << 1) | 1])

    func reflectedBarrettQuotient()->u64
    {
        // Divide x^95 by the degree-32 polynomial and reflect the 64-bit quotient.
        var remainder = 1_u32
        var quotient  = 0_u64
        for 95
        {
            let top = remainder >> 31
            remainder = (remainder << 1) ^ (top != 0 ? CrcPolynomial : 0_u32)
            quotient  = (quotient << 1) | cast(u64, top)
        }

        return Math.reverse(quotient)
    }

    #[Swag.Inline]
    func reduceFolded(value: Math.Simd.U64x2)->u32
    {
        // Fold the portion below x^64 into the upper half. The full-width
        // reflected Barrett reciprocal then removes the quotient in two products.
        let folded  = Math.Simd.clmulLowHigh(value, FoldK3K4) ^ Swag.vecAlign(value, FoldZero, 8)
        let removed = Math.Simd.clmulLowLow(folded, BarrettFactors)
        let reduced = folded ^ Math.Simd.clmulLowHigh(removed, BarrettFactors)
        return cast(u32, reduced[1])
    }

    func reflectedFoldPower(bits: u64)->u64
    {
        var value = 1_u32
        for bits
        {
            value = value >> 31 ? (value << 1) ^ CrcPolynomial : value << 1
        }

        return Math.reverse(cast(u64, value))
    }

    #[Swag.Inline]
    func(Bits: u64) advanceBlock(value: Math.Simd.U64x2)->Math.Simd.U64x2
    {
        const Powers = cast(Math.Simd.U64x2, [#run reflectedFoldPower(Bits + 63),
                                              #run reflectedFoldPower(Bits - 1)])
        return Math.Simd.clmulLowLow(value, Powers) ^ Math.Simd.clmulHighHigh(value, Powers)
    }

    const ShiftMasks = #run buildShiftMasks()

    func buildShiftMasks()->[48] u8
    {
        var masks: #returntype
        for index in 16
        {
            masks[index]      = 0x80
            masks[16 + index] = cast(u8, index)
            masks[32 + index] = 0x80
        }

        return masks
    }

    #[Swag.Inline]
    func finishFold(value: Math.Simd.U64x2, end: const [*] u8, tail: u64)->u32
    {
        if tail == 0
        {
            return reduceFolded(value)

            // The last 16 bytes are already in bounds because at least one full
            // block preceded the tail. Keep only the still-unprocessed bytes.
        }

        let leftMask  = Math.Simd.load(ShiftMasks.buffer + tail)
        let rightMask = Math.Simd.load(ShiftMasks.buffer + tail + 16)
        let bytes     = cast #bit(Math.Simd.U8x16, value)
        let left      = cast #bit(Math.Simd.U64x2, Math.Simd.shuffle(bytes, leftMask))
        let right     = Math.Simd.shuffle(bytes, rightMask)
        let newBytes  = Math.Simd.load(end - 16)
        let selectNew = rightMask == Math.Simd.splat(128_u8)
        let block     = cast #bit(Math.Simd.U64x2, Math.Simd.select(selectNew, newBytes, right))
        return reduceFolded(advanceBlock!{128}(left) ^ block)
    }

    #[Swag.Inline]
    func collapseFourBlocks(first, second, third, fourth: Math.Simd.U64x2)->Math.Simd.U64x2
    {
        let earlier = advanceBlock!{384}(first) ^ advanceBlock!{256}(second)
        let later   = advanceBlock!{128}(third) ^ fourth
        return earlier ^ later
    }

    #[Swag.NoInline]
    func foldShort(crcReg: u32, buffer: const [*] u8, length: u64)->u32
    {
        let seed   = cast(Math.Simd.U64x2, [cast(u64, crcReg), 0_u64])
        let first  = Math.Simd.load(cast(const [*] u64, buffer)) ^ seed
        let second = Math.Simd.load(cast(const [*] u64, buffer + 16))
        if length < 48
        {
            return finishFold(advanceBlock!{128}(first) ^ second, buffer + length, length & 15)
        }

        let third = Math.Simd.load(cast(const [*] u64, buffer + 32))
        if length < 64
        {
            return finishFold(advanceBlock!{256}(first) ^ advanceBlock!{128}(second) ^ third, buffer + length, length & 15)
        }

        let fourth = Math.Simd.load(cast(const [*] u64, buffer + 48))
        let value  = collapseFourBlocks(first, second, third, fourth)
        return finishFold(value, buffer + length, length & 15)
    }

    #[Swag.Inline]
    func foldBlock(value, powers, next: Math.Simd.U64x2)->Math.Simd.U64x2
        => Math.Simd.clmulLowLow(value, powers) ^ Math.Simd.clmulHighHigh(value, powers) ^ next

    // Reflect x^(8 * distance + 32) and x^(8 * distance - 32) into 33-bit factors.
    const PairLow      = (#run reflectedFoldPower(288)) >> 31
    const PairHigh     = (#run reflectedFoldPower(224)) >> 31
    const WideLow      = (#run reflectedFoldPower(1056)) >> 31
    const WideHigh     = (#run reflectedFoldPower(992)) >> 31
    const FoldNextPair = cast(Math.Simd.U64x2, [PairLow, PairHigh])
    const FoldNextWide = [WideLow, WideHigh, WideLow, WideHigh]

    #[Swag.Inline]
    func collapseEightLanes(words: const [*] u64)->Math.Simd.U64x2
    {
        let first  = foldBlock(Math.Simd.load(words), FoldK3K4, Math.Simd.load(words + 2))
        let second = foldBlock(Math.Simd.load(words + 4), FoldK3K4, Math.Simd.load(words + 6))
        let third  = foldBlock(Math.Simd.load(words + 8), FoldK3K4, Math.Simd.load(words + 10))
        let fourth = foldBlock(Math.Simd.load(words + 12), FoldK3K4, Math.Simd.load(words + 14))
        let low    = foldBlock(first, FoldNextPair, second)
        let high   = foldBlock(third, FoldNextPair, fourth)
        return foldBlock(low, FoldK1K2, high)
    }

    func foldWideClmul(crcReg: u32, bytes: const [*] u8, length: u64)->u32
    {
        alias Pair = [4] u64
        let powers = FoldNextWide
        var lanes: [4] Pair
        Memory.copy(cast([*] void, &lanes), cast(const [*] void, bytes), #sizeof(lanes))
        lanes[0, 0] ^= cast(u64, crcReg)

        var offset = 128_u64
        while length - offset >= 128
        {
            let next = bytes + offset
            Swag.vecCarrylessMul2XorPair(&lanes[0], &powers, cast(const *Pair, next), 0x00, 0x11)
            Swag.vecCarrylessMul2XorPair(&lanes[1], &powers, cast(const *Pair, next + 32), 0x00, 0x11)
            Swag.vecCarrylessMul2XorPair(&lanes[2], &powers, cast(const *Pair, next + 64), 0x00, 0x11)
            Swag.vecCarrylessMul2XorPair(&lanes[3], &powers, cast(const *Pair, next + 96), 0x00, 0x11)
            offset += 128
        }

        let value = collapseEightLanes(cast(const [*] u64, &lanes))
        return finishClmul(value, bytes + offset, length - offset)
    }

    alias FoldQuad = [8] u64

    #[Swag.Align(64)]
    struct FoldQuadState
    {
        lanes:   [4] FoldQuad
        factors: FoldQuad
    }

    // Treat the existing state as the first lane, followed by at least three
    // complete input blocks. Advance four lanes before collapsing them.
    #[Swag.NoInline]
    func foldTailGroups(block: Math.Simd.U64x2, bytes: const [*] u8, length: u64)->Math.Simd.U64x2
    {
        var input  = cast(const [*] u64, bytes)
        var first  = block
        var second = Math.Simd.load(input)
        var third  = Math.Simd.load(input + 2)
        var fourth = Math.Simd.load(input + 4)
        input += 6

        var offset = 48_u64
        while offset < length
        {
            first  = foldBlock(first, FoldK1K2, Math.Simd.load(input))
            second = foldBlock(second, FoldK1K2, Math.Simd.load(input + 2))
            third  = foldBlock(third, FoldK1K2, Math.Simd.load(input + 4))
            fourth = foldBlock(fourth, FoldK1K2, Math.Simd.load(input + 6))
            input  += 8
            offset += 64
        }

        return collapseFourBlocks(first, second, third, fourth)
    }

    func foldQuadClmul(crcReg: u32, bytes: const [*] u8, length: u64)->u32
    {
        const LowPower  = (#run reflectedFoldPower(2080)) >> 31
        const HighPower = (#run reflectedFoldPower(2016)) >> 31

        // Use an aligned range for the folding state in an ordinary stack allocation.
        const Alignment   = #alignof(FoldQuadState)
        const ScratchSize = #sizeof(FoldQuadState) + Alignment - 1
        var scratch: [ScratchSize] u8
        let address = (cast(u64, scratch.buffer) + Alignment - 1) & ~(Alignment - 1)
        let state   = cast(*FoldQuadState, address)
        state.factors = [LowPower, HighPower, LowPower, HighPower, LowPower, HighPower, LowPower, HighPower]
        Memory.copy(cast([*] void, &state.lanes), cast(const [*] void, bytes), #sizeof(state.lanes))
        state.lanes[0, 0] ^= cast(u64, crcReg)

        var offset = length & ~255_u64
        let end    = bytes + offset
        var next   = bytes + 256
        while next != end
        {
            Swag.vecCarrylessMul2XorQuad(&state.lanes[0], &state.factors, cast(const *FoldQuad, next), 0x00, 0x11)
            Swag.vecCarrylessMul2XorQuad(&state.lanes[1], &state.factors, cast(const *FoldQuad, next + 64), 0x00, 0x11)
            Swag.vecCarrylessMul2XorQuad(&state.lanes[2], &state.factors, cast(const *FoldQuad, next + 128), 0x00, 0x11)
            Swag.vecCarrylessMul2XorQuad(&state.lanes[3], &state.factors, cast(const *FoldQuad, next + 192), 0x00, 0x11)
            next += 256
        }

        const NextEight = cast(Math.Simd.U64x2, [WideLow, WideHigh])
        let words = cast(const [*] u64, &state.lanes)
        let low   = collapseEightLanes(words)
        let high  = collapseEightLanes(words + 16)
        var value = foldBlock(low, NextEight, high)
        if length - offset >= 48
        {
            // The first group already has the preceding 16-byte state.
            let grouped = ((length - offset + 16) & ~63_u64) - 16
            value  = foldTailGroups(value, bytes + offset, grouped)
            offset += grouped
        }

        return finishClmul(value, bytes + offset, length - offset)
    }

    // Folds at least 80 bytes into the inverted CRC-32 register. Longer buffers
    // advance four 16-byte lanes in parallel before the final Barrett reduction.
    const Crc32TileBytes   = 512 * 1024_u64
    const Crc32MaxTiles    = 32
    const Crc32TileAdvance = #run computeTileAdvance()

    #[Swag.Inline]
    func advanceBit(value: u32)->u32
    {
        return value & 1 ? (value >> 1) ^ 0xEDB8_8320_u32 : value >> 1
    }

    func computeTileAdvance()->u32
    {
        var factor = 0x8000_0000_u32
        for Crc32TileBytes * 8
        {
            factor = advanceBit(factor)
        }
        return factor
    }

    func mergeTile(previous, tile: u32)->u32
    {
        // Multiply by x^(8 * Crc32TileBytes) in the reflected polynomial basis.
        var crc = tile
        var term = previous
        var factor = Crc32TileAdvance
        while factor
        {
            if factor >> 31
            {
                crc ^= term
            }
            term = advanceBit(term)
            factor <<= 1
        }
        return crc
    }

    #[Swag.NoInline]
    func foldParallel(crcReg: u32, bytes: const [*] u8, length: u64)->u32
    {
        var checksum = crcReg
        var offset   = 0_u64
        var results: [Crc32MaxTiles] u32
        while offset < length
        {
            let tiles = Swag.min((length - offset) / Crc32TileBytes, Crc32MaxTiles)
            let source = bytes + offset
            parallel for |source, &results| tile in tiles
            {
                results[tile] = foldClmul(0, source + tile * Crc32TileBytes, Crc32TileBytes)
            }
            for tile in tiles
            {
                checksum = mergeTile(checksum, results[tile])
            }
            offset += tiles * Crc32TileBytes
        }
        return checksum
    }

    #[Swag.NoInline]
    func foldClmul(crcReg: u32, buffer: const [*] u8, length: u64)->u32
    {
        if length >= 8 * Crc32TileBytes and not Swag.jit() and Swag.workerCount() > 1
        {
            var complete = length & ~(Crc32TileBytes - 1)
            let tail = length - complete
            // Keep at least one whole block in the serial remainder when it is nonempty.
            if tail != 0 and tail < 80
            {
                complete -= Crc32TileBytes
            }
            let checksum = foldParallel(crcReg, buffer, complete)
            if complete == length
            {
                return checksum
            }
            return foldClmul(checksum, buffer + complete, length - complete)
        }

        if length >= 1024
        {
            if Swag.hasCpuFeature(.CarrylessMultiply512)
            {
                return foldQuadClmul(crcReg, buffer, length)
            }

            if Swag.hasCpuFeature(.WideCarrylessMultiply)
            {
                return foldWideClmul(crcReg, buffer, length)
            }
        }

        var seed: [2] u64 = [cast(u64, crcReg), 0]

        var buf = cast(const [*] u64, buffer)
        var len = length

        var x1 = Math.Simd.load(buf)
        var x2 = Math.Simd.load(buf + 2)
        var x3 = Math.Simd.load(buf + 4)
        var x4 = Math.Simd.load(buf + 6)

        x1 ^= Math.Simd.load(cast(const [*] u64, &seed[0]))

        let k = FoldK1K2
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

        let value = collapseFourBlocks(x1, x2, x3, x4)
        return finishClmul(value, cast(const [*] u8, buf), len)
    }

    #[Swag.Inline]
    func finishClmul(block: Math.Simd.U64x2, buffer: const [*] u8, length: u64)->u32
    {
        var value  = block
        var offset = 0_u64
        while length - offset >= 16
        {
            value  = foldBlock(value, FoldK3K4, Math.Simd.load(cast(const [*] u64, buffer + offset)))
            offset += 16
        }

        return finishFold(value, buffer + length, length - offset)
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
        .currentValue = updateValue(data, .currentValue)
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes the CRC-32 checksum of `buffer` in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8)->u32 => updateValue(buffer, 0)
}
