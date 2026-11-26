#global namespace Hash
#global #[Swag.Safety(.Overflow, false)]

using Swag, Core.Math

// Computes a CRC-64 checksum incrementally.
public struct Crc64
{
    internal
    {
        currentValue: u64
        kind:         Crc64Kind
    }
}

// Selects the CRC-64 polynomial and reflection convention.
public enum Crc64Kind
{
    Ecma182     // CRC-64/ECMA-182.
    Iso         // CRC-64/ISO.
    IsoXz       // CRC-64/XZ.
}

private impl Crc64
{
    alias ChecksumRow   = [256] u64
    alias ChecksumTable = [8] ChecksumRow

    const EcmaPolynomial = 0x42F0_E1EB_A9EA_3693'u64
    const IsoPolynomial  = 0x1B'u64
    const TileBytes      = 512 * 1024
    const MaxTiles       = 32

    const Ecma182Table = #run buildTable(EcmaPolynomial, reflected: false)
    const IsoTable     = #run buildTable(Math.reverse(IsoPolynomial), reflected: true)
    const XzTable      = #run buildTable(Math.reverse(EcmaPolynomial), reflected: true)

    func buildTable(polynomial: u64, reflected: bool)->ChecksumTable
    {
        var table: ChecksumTable
        for index in 256
        {
            var value = cast(u64, index)
            if reflected
            {
                for 8 do
                    value = value & 1 ? (value >> 1) ^ polynomial : value >> 1
            }
            else
            {
                value <<= 56
                for 8 do
                    value = value >> 63 ? (value << 1) ^ polynomial : value << 1

                // Store ECMA-182 with its next byte's index in the low bits as well.
                value = Swag.byteSwap(value)
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

    // A reflected 64x64 product reverses across 127 positions. Reverse the powers
    // and subtract one from each exponent to match the 128-bit block representation.
    func foldPower(bits: u64, polynomial: u64, reflected: bool)->u64
    {
        var power = 1'u64
        for reflected ? bits - 1 : bits do
            power = power >> 63 ? (power << 1) ^ polynomial : power << 1
        return reflected ? Math.reverse(power) : power
    }

    // Returns the lower 64 bits of the polynomial quotient of x^128 by x^64 + polynomial.
    func barrettQuotient(polynomial: u64)->u64
    {
        var remainder = polynomial
        var quotient  = 0'u64
        for 64
        {
            let bit = remainder >> 63
            remainder = bit ? (remainder << 1) ^ polynomial : remainder << 1
            quotient  = (quotient << 1) | bit
        }

        return quotient
    }

    #[Swag.Inline]
    func(Polynomial: u64) reduceMsb(value: Simd.U64x2)->u64
    {
        const Factors = cast(Simd.U64x2, [#run barrettQuotient(Polynomial), Polynomial])
        let quotient = value ^ Simd.clmulHighLow(value, Factors)
        let reduced  = value ^ Simd.clmulHighHigh(quotient, Factors)
        return reduced[0]
    }

    #[Swag.Inline]
    func(Reflected: bool) orientBlock(block: Simd.U8x16)->Simd.U64x2
    {
        #static if Reflected do
            return cast #bit(Simd.U64x2, block)
        else
        {
            const ReverseBytes = cast(Simd.U8x16, [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
            return cast #bit(Simd.U64x2, Simd.shuffle(block, ReverseBytes))
        }
    }

    #[Swag.Inline]
    func(Reflected: bool) readFoldBlock(source: const [*] u8)->Simd.U64x2
        => orientBlock'Reflected(Simd.load(source))

    #[Swag.Inline]
    func multiplyHalves(value, powers: Simd.U64x2)->Simd.U64x2
        => Simd.clmulLowLow(value, powers) ^ Simd.clmulHighHigh(value, powers)

    #[Swag.Inline]
    func(Polynomial: u64, Reflected: bool) reduceFolded(value: Simd.U64x2)->u64
    {
        #static if Reflected
        {
            // Reflect the quotient and divisor at the same scale as foldPower.
            const Mu      = #run barrettQuotient(Polynomial)
            const Factors = cast(Simd.U64x2, [(#run Math.reverse(Mu)) << 1 | 1,
                                              (#run Math.reverse(Polynomial)) << 1])
            let quotient = Simd.clmulLowLow(value, Factors)
            let reduced  = Simd.clmulLowHigh(quotient, Factors)
            return value[1] ^ quotient[0] ^ reduced[1]
        }
        else do
            return Swag.byteSwap(reduceMsb'Polynomial(value))
    }

    #[Swag.Inline]
    func(Polynomial: u64, Reflected: bool, Bits: u64) multiplyShortBlock(block: Simd.U64x2)->Simd.U64x2
    {
        const LowBits  = Reflected ? Bits : Bits - 64
        const HighBits = Reflected ? Bits - 64 : Bits
        const Powers   = cast(Simd.U64x2, [#run foldPower(LowBits, Polynomial, Reflected),
                                           #run foldPower(HighBits, Polynomial, Reflected)])
        return multiplyHalves(block, Powers)
    }

    #[Swag.Inline]
    func(Polynomial: u64, Reflected: bool) foldFourBlocks(bytes: const [*] u8, initial: u64)->u64
    {
        // Apply each word's final power independently, including the 64 implicit zero bits.
        let seed         = cast(Simd.U64x2, [initial, 0'u64])
        let initialBlock = readFoldBlock'Reflected(bytes) ^ orientBlock'Reflected(cast #bit(Simd.U8x16, seed))
        let first        = multiplyShortBlock'(Polynomial, Reflected, 512)(initialBlock)
        let second       = multiplyShortBlock'(Polynomial, Reflected, 384)(readFoldBlock'Reflected(bytes + 16))
        let third        = multiplyShortBlock'(Polynomial, Reflected, 256)(readFoldBlock'Reflected(bytes + 32))
        let fourth       = multiplyShortBlock'(Polynomial, Reflected, 128)(readFoldBlock'Reflected(bytes + 48))
        return reduceFolded'(Polynomial, Reflected)((first ^ second) ^ (third ^ fourth))
    }

    func(Polynomial: u64, Reflected: bool) foldBlocks(bytes: const [*] u8, length, initial: u64)->u64
    {
        const LowDegree  = Reflected ? 64'u64 : 0'u64
        const HighDegree = 64 - LowDegree
        const NextBlock  = cast(Simd.U64x2, [#run foldPower(128 + LowDegree, Polynomial, Reflected),
                                             #run foldPower(128 + HighDegree, Polynomial, Reflected)])
        const NextPair = cast(Simd.U64x2, [#run foldPower(256 + LowDegree, Polynomial, Reflected),
                                           #run foldPower(256 + HighDegree, Polynomial, Reflected)])
        const NextGroup = cast(Simd.U64x2, [#run foldPower(512 + LowDegree, Polynomial, Reflected),
                                            #run foldPower(512 + HighDegree, Polynomial, Reflected)])

        #[Swag.Inline]
        func fold(value, powers, next: Simd.U64x2)->Simd.U64x2
            => multiplyHalves(value, powers) ^ next

        let seed      = cast(Simd.U64x2, [initial, 0'u64])
        let blockSeed = orientBlock'Reflected(cast #bit(Simd.U8x16, seed))
        var first     = readFoldBlock'Reflected(bytes) ^ blockSeed
        var second    = readFoldBlock'Reflected(bytes + 16)
        var third     = readFoldBlock'Reflected(bytes + 32)
        var fourth    = readFoldBlock'Reflected(bytes + 48)

        // Advance four independent lanes to hide carry-less multiplication latency.
        var offset = 64'u64
        while length - offset >= 64
        {
            first  = fold(first, NextGroup, readFoldBlock'Reflected(bytes + offset))
            second = fold(second, NextGroup, readFoldBlock'Reflected(bytes + offset + 16))
            third  = fold(third, NextGroup, readFoldBlock'Reflected(bytes + offset + 32))
            fourth = fold(fourth, NextGroup, readFoldBlock'Reflected(bytes + offset + 48))
            offset += 64
        }

        // Collapse the lanes in byte order and finish the complete blocks.
        first = fold(first, NextBlock, second)
        third = fold(third, NextBlock, fourth)
        first = fold(first, NextPair, third)
        while offset < length
        {
            first  = fold(first, NextBlock, readFoldBlock'Reflected(bytes + offset))
            offset += 16
        }

        // Carry the usual 64 zero bits implicit in a width-64 CRC into the reduction.
        const FinalPowers = cast(Simd.U64x2, [#run foldPower(64 + LowDegree, Polynomial, Reflected),
                                              #run foldPower(64 + HighDegree, Polynomial, Reflected)])
        return reduceFolded'(Polynomial, Reflected)(multiplyHalves(first, FinalPowers))
    }

    func(Polynomial: u64, Reflected: bool) foldParallel(bytes: const [*] u8, length, initial: u64, table: const [..] ChecksumRow)->u64
    {
        // A tile checksum computed from zero is independent of every earlier tile.
        // Concatenation advances the previous remainder by the tile's bits, then exclusive-ors
        // the independent contribution. Use the ordinary, MSB-first polynomial for merging.
        const Advance = cast(Simd.U64x2, [#run foldPower(TileBytes * 8, Polynomial, reflected: false), 0'u64])

        #[Swag.Inline]
        func canonical(raw: u64)->u64
        {
            #static if Reflected do
                return Math.reverse(raw)
            else do
                return Swag.byteSwap(raw)
        }

        var checksum = canonical(initial)
        var offset   = 0'u64
        var results: [MaxTiles] u64
        while length - offset >= TileBytes
        {
            let tiles  = Swag.min((length - offset) / TileBytes, MaxTiles)
            let source = bytes + offset
            parallel for |source, &results| tile in tiles do
                results[tile] = foldBlocks'(Polynomial, Reflected)(source + tile * TileBytes, TileBytes, 0)
            for tile in tiles
            {
                let state    = cast(Simd.U64x2, [checksum, 0'u64])
                let advanced = reduceMsb'Polynomial(Simd.clmulLowLow(state, Advance))
                checksum = advanced ^ canonical(results[tile])
            }

            offset += tiles * TileBytes
        }

        let raw       = canonical(checksum)
        let remaining = length - offset
        if remaining >= 64 do
            return foldBlocks'(Polynomial, Reflected)(bytes + offset, remaining, raw)
        return updateTable(bytes + offset, remaining, raw, table)
    }

    #[Swag.Inline]
    func(Polynomial: u64, Reflected: bool, Parallel: bool) foldInput(bytes: const [*] u8, length, initial: u64, table: const [..] ChecksumRow)->u64
    {
        #static if Parallel do
            return foldParallel'(Polynomial, Reflected)(bytes, length, initial, table)
        else
        {
            discard table
            if length == 64 do
                return foldFourBlocks'(Polynomial, Reflected)(bytes, initial)
            return foldBlocks'(Polynomial, Reflected)(bytes, length, initial)
        }
    }

    #[Swag.NoInline]
    func(Parallel: bool) foldAligned(bytes: const [*] u8, length, previous: u64, kind: Crc64Kind)->u64
    {
        switch #complete kind
        {
        case .Ecma182:
            let crc = foldInput'(EcmaPolynomial, false, Parallel)(bytes, length, Swag.byteSwap(previous), Ecma182Table)
            return Swag.byteSwap(crc)

        case .Iso:
            return ~foldInput'(IsoPolynomial, true, Parallel)(bytes, length, ~previous, IsoTable)

        case .IsoXz:
            return ~foldInput'(EcmaPolynomial, true, Parallel)(bytes, length, ~previous, XzTable)
        }
    }

    #[ConstExpr, Swag.Safety(.All, false)]
    func updateTable(bytes: const [*] u8, length, initial: u64, table: const [..] ChecksumRow)->u64
    {
        var crc       = initial
        var current   = bytes
        var remaining = length
        while remaining >= 8
        {
            let word  = Math.littleEndianToNative(cast(const [*] u64, current)[0])
            let mixed = word ^ crc
            crc = table[7, mixed & 0xFF] ^
                  table[6, (mixed >> 8) & 0xFF] ^
                  table[5, (mixed >> 16) & 0xFF] ^
                  table[4, (mixed >> 24) & 0xFF] ^
                  table[3, (mixed >> 32) & 0xFF] ^
                  table[2, (mixed >> 40) & 0xFF] ^
                  table[1, (mixed >> 48) & 0xFF] ^
                  table[0, mixed >> 56]
            current   += 8
            remaining -= 8
        }

        for index in remaining do
            crc = (crc >> 8) ^ table[0, (crc & 0xFF) ^ current[index]]
        return crc
    }

    #[ConstExpr, Swag.Inline, Swag.Safety(.All, false)]
    func updateValue(data: const [..] u8?, previous: u64, kind: Crc64Kind)->u64
    {
        var length = data.count
        if length == 0 do
            return previous

        var crc   = previous
        var bytes = cast(const [*] u8, unwrap data.buffer)
        #static if not BIG_ENDIAN
        {
            if length >= 64 and Swag.hasCpuFeature(.CarrylessMultiply)
            {
                let folded = length & ~15'u64
                if folded >= 4 * TileBytes and not Swag.jit() and Swag.workerCount() > 1 do
                    crc = foldAligned'true(bytes, folded, crc, kind)
                else do
                    crc = foldAligned'false(bytes, folded, crc, kind)
                bytes  += folded
                length -= folded
                if length == 0 do
                    return crc
            }
        }

        switch #complete kind
        {
        case .Ecma182: return Swag.byteSwap(updateTable(bytes, length, Swag.byteSwap(crc), Ecma182Table))
        case .Iso:     return ~updateTable(bytes, length, ~crc, IsoTable)
        case .IsoXz:   return ~updateTable(bytes, length, ~crc, XzTable)
        }
    }
}

public impl Crc64
{
    // Resets the checksum and selects the algorithm used by subsequent updates.
    mtd reset(kind = Crc64Kind.Ecma182)
    {
        Swag.init(me, 1)
        .kind = kind
    }

    // Includes `data` in the running checksum.
    #[ConstExpr]
    mtd update(data: const [..] u8?)
    {
        .currentValue = updateValue(data, .currentValue, .kind)
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes the CRC-64 checksum of `buffer` with the `kind` algorithm in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8, kind = Crc64Kind.Ecma182)->u64 => updateValue(buffer, 0, kind)
}
