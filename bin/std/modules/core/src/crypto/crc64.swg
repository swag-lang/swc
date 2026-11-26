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

    func(Polynomial: u64, Reflected: bool) foldBlocks(bytes: const [*] u8, length, initial: u64)->u64
    {
        const ReverseBytes = cast(Simd.U8x16, [15'u8, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
        const LowDegree    = Reflected ? 64'u64 : 0'u64
        const HighDegree   = 64 - LowDegree
        const NextBlock    = cast(Simd.U64x2, [#run foldPower(128 + LowDegree, Polynomial, Reflected),
                                               #run foldPower(128 + HighDegree, Polynomial, Reflected)])
        const NextPair = cast(Simd.U64x2, [#run foldPower(256 + LowDegree, Polynomial, Reflected),
                                           #run foldPower(256 + HighDegree, Polynomial, Reflected)])
        const NextGroup = cast(Simd.U64x2, [#run foldPower(512 + LowDegree, Polynomial, Reflected),
                                            #run foldPower(512 + HighDegree, Polynomial, Reflected)])

        #[Swag.Inline]
        func orient(block: Simd.U8x16)->Simd.U8x16
        {
            #static if Reflected do
                return block
            else do
                return Simd.shuffle(block, ReverseBytes)
        }

        #[Swag.Inline]
        func loadBlock(source: const [*] u8)->Simd.U64x2 => cast #bit(Simd.U64x2, orient(Simd.load(source)))

        #[Swag.Inline]
        func fold(value, powers, next: Simd.U64x2)->Simd.U64x2
            => Simd.clmulLowLow(value, powers) ^ Simd.clmulHighHigh(value, powers) ^ next

        let seed      = cast(Simd.U64x2, [initial, 0'u64])
        let blockSeed = cast #bit(Simd.U64x2, orient(cast #bit(Simd.U8x16, seed)))
        var first     = loadBlock(bytes) ^ blockSeed
        var second    = loadBlock(bytes + 16)
        var third     = loadBlock(bytes + 32)
        var fourth    = loadBlock(bytes + 48)

        // Advance four independent lanes to hide carry-less multiplication latency.
        var offset = 64'u64
        while length - offset >= 64
        {
            first  = fold(first, NextGroup, loadBlock(bytes + offset))
            second = fold(second, NextGroup, loadBlock(bytes + offset + 16))
            third  = fold(third, NextGroup, loadBlock(bytes + offset + 32))
            fourth = fold(fourth, NextGroup, loadBlock(bytes + offset + 48))
            offset += 64
        }

        // Collapse the lanes in byte order and finish the complete blocks.
        first = fold(first, NextBlock, second)
        third = fold(third, NextBlock, fourth)
        first = fold(first, NextPair, third)
        while offset < length
        {
            first  = fold(first, NextBlock, loadBlock(bytes + offset))
            offset += 16
        }

        // Carry the usual 64 zero bits implicit in a width-64 CRC into the reduction.
        const FinalPowers = cast(Simd.U64x2, [#run foldPower(64 + LowDegree, Polynomial, Reflected),
                                              #run foldPower(64 + HighDegree, Polynomial, Reflected)])
        const Zero = cast(Simd.U64x2, [0'u64, 0])
        const Mu   = #run barrettQuotient(Polynomial)
        let finalBlock = fold(first, FinalPowers, Zero)

        #static if Reflected
        {
            // Reflect the quotient and divisor at the same scale as foldPower.
            const Factors = cast(Simd.U64x2, [(#run Math.reverse(Mu)) << 1 | 1,
                                              (#run Math.reverse(Polynomial)) << 1])
            let quotient = Simd.clmulLowLow(finalBlock, Factors)
            let reduced  = Simd.clmulLowHigh(quotient, Factors)
            return finalBlock[1] ^ quotient[0] ^ reduced[1]
        }
        else
        {
            const Factors = cast(Simd.U64x2, [Mu, Polynomial])
            let quotient = finalBlock ^ Simd.clmulHighLow(finalBlock, Factors)
            let reduced  = finalBlock ^ Simd.clmulHighHigh(quotient, Factors)
            return Swag.byteSwap(reduced[0])
        }
    }

    #[Swag.NoInline]
    mtd foldAligned(bytes: const [*] u8, length: u64)
    {
        switch #complete .kind
        {
        case .Ecma182:
            let crc = foldBlocks'(EcmaPolynomial, false)(bytes, length, Swag.byteSwap(.currentValue))
            .currentValue = Swag.byteSwap(crc)

        case .Iso:
            .currentValue = ~foldBlocks'(IsoPolynomial, true)(bytes, length, ~.currentValue)

        case .IsoXz:
            .currentValue = ~foldBlocks'(EcmaPolynomial, true)(bytes, length, ~.currentValue)
        }
    }

    #[ConstExpr, Swag.Safety(.All, false)]
    func updateTable(bytes: const [*] u8, length, initial: u64, table: const [..] ChecksumRow)->u64
    {
        var crc    = initial
        var offset = 0'u64
        while length - offset >= 8
        {
            let word  = Math.littleEndianToNative(cast(const [*] u64, bytes + offset)[0])
            let mixed = word ^ crc
            crc = table[7, mixed & 0xFF] ^
                  table[6, (mixed >> 8) & 0xFF] ^
                  table[5, (mixed >> 16) & 0xFF] ^
                  table[4, (mixed >> 24) & 0xFF] ^
                  table[3, (mixed >> 32) & 0xFF] ^
                  table[2, (mixed >> 40) & 0xFF] ^
                  table[1, (mixed >> 48) & 0xFF] ^
                  table[0, mixed >> 56]
            offset += 8
        }

        for index in offset until length do
            crc = (crc >> 8) ^ table[0, (crc & 0xFF) ^ bytes[index]]
        return crc
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
    #[ConstExpr, Swag.Safety(.All, false)]
    mtd update(data: const [..] u8?)
    {
        var length = data.count
        if length == 0 do
            return

        var bytes = cast(const [*] u8, unwrap data.buffer)
        #static if not BIG_ENDIAN
        {
            if length >= 64 and Swag.hasCpuFeature(.CarrylessMultiply)
            {
                let folded = length & ~15'u64
                .foldAligned(bytes, folded)
                bytes  += folded
                length -= folded
                if length == 0 do
                    return
            }
        }

        switch #complete .kind
        {
        case .Ecma182:
            let crc = updateTable(bytes, length, Swag.byteSwap(.currentValue), Ecma182Table)
            .currentValue = Swag.byteSwap(crc)

        case .Iso:
            .currentValue = ~updateTable(bytes, length, ~.currentValue, IsoTable)

        case .IsoXz:
            .currentValue = ~updateTable(bytes, length, ~.currentValue, XzTable)
        }
    }

    // Returns the checksum accumulated since construction or the latest [[reset]].
    mtd value() => .currentValue

    // Computes the CRC-64 checksum of `buffer` with the `kind` algorithm in one operation.
    #[Swag.ConstExpr]
    func compute(buffer: const [..] u8, kind = Crc64Kind.Ecma182)->u64
    {
        var v: Crc64
        v.reset(kind)
        v.update(buffer)
        return v.value()
    }
}
