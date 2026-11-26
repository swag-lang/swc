//! Format: Joint Photographic Experts Group (JPEG) decoder component.
//! Supported: Baseline and progressive Huffman-coded grayscale, YCbCr, directly sampled RGB, and CMYK or YCCK images.
//! Not supported: Arithmetic coding, lossless JPEG, and unsupported chroma sampling layouts.
//! Role: This file owns progressive scan coefficient refinement.
//
#global namespace Jpg

using Swag, Core, Core.Errors

impl Decoder
{
    func coeffBufOpen(blkNumX, blkNumY: s32)->CoeffBuf
    {
        with var result: #returntype
        {
            .blockNumX = blkNumX
            .blockNumY = blkNumY
            let blocks = cast(u64, blkNumX) * blkNumY
            .values.resize(blocks * 64)
            .nonzeroAc.resize(blocks)
        }

        return result
    }

    mtd decodeBlockDcFirst(cmpId: u32, blkX, blkY: s32) fail
    {
        var p = coeffBufGetp(.coefficients[cmpId], blkX, blkY)
        var s = .huffDecode(&.h[.compDcTab[cmpId]])
        if s != 0
        {
            s = extendSign(.getBits2(s), s)
        }

        s    += .lastDcVal[cmpId]
        .lastDcVal[cmpId] = s
        p[0] = cast(s16, (s << .successiveLow))
    }

    mtd decodeBlockDcRefine(cmpId: u32, blkX, blkY: s32) fail
    {
        if .getBits2(1)
        {
            var p = coeffBufGetp(.coefficients[cmpId], blkX, blkY)
            p[0] |= (1's16 << .successiveLow)
        }
    }

    mtd decodeBlockAcFirst(p: [*] s16, present: *u64, table: *HuffTables) fail
    {
        if .eobRun
        {
            .eobRun -= 1
            return
        }

        var mask = present[]
        for var k = .spectralStart; k <= .spectralEnd; k += 1
        {
            var s = .huffDecode(table)
            var r = s >> 4
            s &= 0x0F

            if s
            {
                k += r
                if k > 63 do
                    fail InvalidFormatError{"decode error"}
                let rbits = .getBits2(s)
                if s > 15 do
                    fail InvalidFormatError{"decode error"}

                s = extendSign(rbits, s)
                let coefficient = cast(s16, (s << .successiveLow))
                p[Zag[k]] = coefficient
                let bit = 1'u64 << k
                mask = (mask & ~bit) | (coefficient != 0 ? bit : 0)
            }
            else
            {
                if r == 15
                {
                    k += 15
                    if k > 63 do
                        fail InvalidFormatError{"decode error"}
                }
                else
                {
                    .eobRun = 1 << r
                    if r do
                        .eobRun += .getBits2(r)
                    .eobRun -= 1
                    break
                }
            }
        }

        present[] = mask
    }

    #[Swag.Inline]
    mtd refineCoefficient(coeff: *s16, bit: s16)
    {
        let value = coeff[]
        if .getBits2(1) and (value & bit) == 0 do
            coeff[] = value + (value < 0 ? -bit : bit)
    }

    mtd decodeBlockAcRefine(p: [*] s16, present: *u64, table: *HuffTables) fail
    {
        let bit       = cast(s16, 1 << .successiveLow)
        let first     = .spectralStart
        let last      = .spectralEnd
        let band      = (Swag.U64.Max << first) & (Swag.U64.Max >> (63 - last))
        var remaining = present[] & band
        var k         = first

        while .eobRun == 0 and k <= last
        {
            let symbol = .huffDecode(table)
            var run    = symbol >> 4
            let size   = symbol & 15
            var coefficient: s16
            if size
            {
                if size != 1 do
                    fail InvalidFormatError{"decode error"}
                coefficient = .getBits2(1) ? bit : -bit
            }
            elif run != 15
            {
                .eobRun = (1 << run) + (run ? .getBits2(run) : 0)
                break
            }

            // Refinement bits are stored only for occupied positions, while the run counts
            // vacant positions. Skip directly to the next occupied index in the scan band.
            while remaining
            {
                let occupied = cast(s32, Swag.trailingZeros(remaining))
                let zeros    = occupied - k
                if run < zeros do
                    break
                run -= zeros
                .refineCoefficient(&p[Zag[occupied]], bit)
                remaining &= remaining - 1
                k         = occupied + 1
            }

            k = Math.min(k + run, last + 1)
            if coefficient and k < 64
            {
                p[Zag[k]] = coefficient
                present[] |= 1'u64 << k
            }

            k += 1
        }

        if .eobRun
        {
            while remaining
            {
                let occupied = cast(s32, Swag.trailingZeros(remaining))
                .refineCoefficient(&p[Zag[occupied]], bit)
                remaining &= remaining - 1
            }

            .eobRun -= 1
        }
    }

    // An AC scan always visits one component in coefficient-block order.
    mtd decodeAcScan(refinementScan: bool) fail
    {
        let component    = .compList[0]
        let table        = &.h[.compAcTab[component]]
        let coefficients = &.coefficients[component]
        let stride       = cast(u64, coefficients.blockNumX) * 64
        var row          = coefficients.values.storage()
        var presenceRow  = coefficients.nonzeroAc.storage()
        for .mcusPerCol
        {
            var block    = row
            var presence = presenceRow
            for .mcusPerRow
            {
                if .restartInterval and .restartsLeft == 0 do
                    try .restartProcess()
                if refinementScan do
                    try .decodeBlockAcRefine(block, &presence[0], table)
                else do
                    try .decodeBlockAcFirst(block, &presence[0], table)
                .restartsLeft -= 1
                block         += 64
                presence      += 1
            }

            row         += stride
            presenceRow += coefficients.blockNumX
        }
    }

    mtd decodeDcScan(refinementScan: bool) fail
    {
        var blockMcutX: [MaxComponents] s32
        var blockMcutY: [MaxComponents] s32

        for .mcusPerCol
        {
            Memory.clear(blockMcutX, #sizeof(blockMcutX))
            for .mcusPerRow
            {
                var blockMcuOfsX = 0
                var blockMcuOfsY = 0

                if .restartInterval and (.restartsLeft == 0) do
                    try .restartProcess()

                for mcuBlock in .blocksPerMcu
                {
                    let componentId = .mcuOrg[mcuBlock]
                    let blkX        = blockMcutX[componentId] + blockMcuOfsX
                    let blkY        = blockMcutY[componentId] + blockMcuOfsY
                    if refinementScan do
                        try .decodeBlockDcRefine(componentId, blkX, blkY)
                    else do
                        try .decodeBlockDcFirst(componentId, blkX, blkY)

                    if .compsInScan == 1
                    {
                        blockMcutX[componentId] += 1
                    }
                    else
                    {
                        blockMcuOfsX += 1
                        if blockMcuOfsX == .compSampH[componentId]
                        {
                            blockMcuOfsX = 0
                            blockMcuOfsY += 1
                            if blockMcuOfsY == .compSampV[componentId]
                            {
                                blockMcuOfsY = 0
                                blockMcutX[componentId] += .compSampH[componentId]
                            }
                        }
                    }
                }

                .restartsLeft -= 1
            }

            if .compsInScan == 1
            {
                blockMcutY[.compList[0]] += 1
            }
            else
            {
                for n in .compsInScan
                {
                    let componentId = .compList[n]
                    blockMcutY[componentId] += .compSampV[componentId]
                }
            }
        }
    }

    mtd validateProgressiveScan() fail
    {
        if .spectralStart > .spectralEnd or .spectralEnd > 63 do
            fail InvalidFormatError{"bad sos spectral"}
        if .spectralStart == 0 ? .spectralEnd != 0 : .compsInScan != 1 do
            fail InvalidFormatError{"bad sos spectral"}
        if .successiveHigh != 0 and .successiveLow != .successiveHigh - 1 do
            fail InvalidFormatError{"bad sos successive"}
    }

    mtd initProgressive() fail
    {
        for i in .compsInFrame do
            .coefficients[i] = coeffBufOpen(.maxMcusPerRow * .compSampH[i], .maxMcusPerCol * .compSampV[i])

        for
        {
            let res = try .initScan()
            if not res do
                break

            let refinementScan = .successiveHigh != 0
            if .spectralStart == 0 do
                try .decodeDcScan(refinementScan)
            else do
                try .decodeAcScan(refinementScan)

            .primeMarkerBits()
        }

        if .lastMarkerSynthetic do
            fail InvalidFormatError{"JPEG data ends before the end-of-image marker"}

        // The masks have no further use once every scan has been decoded.
        for &component in .coefficients do
            component.nonzeroAc.free()

        // The entropy scan stores coefficients in natural order. Reorder each table once so
        // dequantization can multiply an entire row of a block in one operation.
        for &table in .quant where not table.isEmpty()
        {
            var natural: [64] s16
            for i in 64 do
                natural[Zag[i]] = table[i]
            Memory.copy(table.storage(), &natural[0], #sizeof(natural))
        }

        .compsInScan = .compsInFrame
        for i in .compsInFrame do
            .compList[i] = i
        .calcMcuBlockOrder()
    }
}
