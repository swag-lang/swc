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
            let blocks     = cast(u64, blkNumX) * blkNumY
            let valueCount = blocks * 64
            .values.reserve(valueCount)
            Memory.clear(.values.storage(), valueCount * #sizeof(s16))
            .values.count = valueCount
            .nonzeroAc.reserve(blocks)
            Memory.clear(.nonzeroAc.storage(), blocks * #sizeof(u64))
            .nonzeroAc.count = blocks
        }

        return result
    }

    mtd decodeBlockDcFirst(cmpId: u32, blkX, blkY: s32)
    {
        var p = coeffBufGetp(.coefficients[cmpId], blkX, blkY)
        var s = .huffDecode(&.h[.compDcTab[cmpId]])
        if s != 0
        {
            s = extendSign(.readEntropyBits(s), s)
        }

        s    += .lastDcVal[cmpId]
        .lastDcVal[cmpId] = s
        p[0] = cast(s16, (s << .successiveLow))
    }

    mtd decodeBlockDcRefine(cmpId: u32, blkX, blkY: s32)
    {
        if .readEntropyBits(1)
        {
            var p = coeffBufGetp(.coefficients[cmpId], blkX, blkY)
            p[0] |= (1_s16 << .successiveLow)
        }
    }

    // A short AC prefix can carry both its Huffman symbol and its signed amplitude.
    #[Swag.Inline]
    mtd decodeProgressiveAc(table: *HuffTables)->s32
    {
        let entry = table.lookUp[.entropyBits >> (64 - HuffLookupBits)]
        if entry < 0 do
            return .decodeLongHuffCode(table, entry, HuffLookupBits)
        if entry >= 1 << 24
        {
            .skipEntropyBits(entry >> 24)
            return entry
        }

        .skipEntropyBits(entry >> 8)
        return entry & 255
    }

    mtd decodeBlockAcFirst(p: [*] s16, present: *u64, table: *HuffTables)->bool
    {
        var mask = present[]
        for var k = .spectralStart; k <= .spectralEnd; k += 1
        {
            let symbol = .decodeProgressiveAc(table)
            let r      = (symbol >> 4) & 15
            let s      = symbol & 15

            if s
            {
                k += r
                if k > 63
                {
                    fail InvalidFormatError{"decode error"}
                }

                let rbits = .getBits2(s)
                if s > 15
                {
                    fail InvalidFormatError{"decode error"}
                }

                s         = extendSign(rbits, s)
                p[Zag[k]] = cast(s16, (s << .successiveLow))
            }
            else
            {
                if r == 15
                {
                    k += 15
                    if k > 63
                    {
                        fail InvalidFormatError{"decode error"}
                    }
                }
                else
                {
                    .eobRun = 1 << r
                    if r
                    {
                        .eobRun += .getBits2(r)
                    }

                    .eobRun -= 1
                    break
                }
            }
        }

        present[] = mask
        return true
    }

    #[Swag.Inline]
    mtd refineCoefficient(coeff: *s16, bit: s16)
    {
        let value = coeff[]
        if .readEntropyBits(1) and (value & bit) == 0
        {
            if .spectralEnd >= 64
            {
                fail InvalidFormatError{"decode error"}
            }

    mtd decodeBlockAcRefine(p: [*] s16, present: *u64, table: *HuffTables, band: u64, bit: s16)->bool
    {
        let first     = .spectralStart
        let last      = .spectralEnd
        var remaining = present[] & band
        var k         = first

        while .eobRun == 0 and k <= last
        {
            let symbol = .decodeProgressiveAc(table)
            var run    = (symbol >> 4) & 15
            let size   = symbol & 15
            var coefficient: s16
            if size
            {
                var s = .huffDecode(&.h[.compAcTab[cmpId]])
                var r = s >> 4
                s &= 15

                if s
                {
                    if s != 1
                    {
                        fail InvalidFormatError{"decode error"}
                    }

                    if .getBits2(1)
                    {
                        s = p1
                    }
                    else
                    {
                        s = m1
                    }
                }
                else
                {
                    if r != 15
                    {
                        .eobRun = 1 << r
                        if r
                        {
                            .eobRun += .getBits2(r)
                        }

                        break
                    }
                }

                for
                {
                    var thisCoef = p + Zag[k]
                    if thisCoef[] != 0
                    {
                        if .getBits2(1)
                        {
                            if (thisCoef[] & cast(s16, p1)) == 0
                            {
                                if thisCoef[] >= 0
                                {
                                    thisCoef[] += cast(s16, p1)
                                }
                                else
                                {
                                    thisCoef[] += cast(s16, m1)
                                }
                            }
                        }
                    }
                    else
                    {
                        r -= 1
                        if r < 0
                        {
                            break
                        }
                    }

                    k += 1
                    if k > .spectralEnd
                    {
                        break
                    }
                }

                if s and (k < 64)
                {
                    p[Zag[k]] = cast(s16, s)
                }

                k += 1
            }
            elif run != 15
            {
                .eobRun = (1 << run) + (run ? .readEntropyBits(run) : 0)
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
                .refineCoefficient(&p[ZigzagToTransposed[occupied]], bit)
                remaining &= remaining - 1
                k         = occupied + 1
            }

            k = Math.min(k + run, last + 1)
            if coefficient and k < 64
            {
                p[ZigzagToTransposed[k]] = coefficient
                present[] |= 1'u64 << k
            }

            k += 1
        }

        if .eobRun
        {
            if .spectralEnd >= 64
            {
                fail InvalidFormatError{"decode error"}
            }

            while k <= .spectralEnd
            {
                var thisCoef = p + Zag[k]
                if thisCoef[] != 0
                {
                    if .getBits2(1)
                    {
                        if (thisCoef[] & cast(s16, p1)) == 0
                        {
                            if thisCoef[] >= 0
                            {
                                thisCoef[] += cast(s16, p1)
                            }
                            else
                            {
                                thisCoef[] += cast(s16, m1)
                            }
                        }
                    }
                }

                k += 1
            }

            .eobRun -= 1
        }

        return true
    }

    // An AC scan always visits one component in coefficient-block order.
    mtd(REFINE: bool) decodeAcScan() fail
    {
        let component    = .compList[0]
        let table        = &.h[.compAcTab[component]]
        let coefficients = &.coefficients[component]
        let stride       = cast(u64, coefficients.blockNumX) * 64
        let band         = (Swag.U64.Max << .spectralStart) & (Swag.U64.Max >> (63 - .spectralEnd))
        let bit          = cast(s16, 1 << .successiveLow)
        var row          = coefficients.values.storage()
        var presenceRow  = coefficients.nonzeroAc.storage()
        for .mcusPerCol
        {
            var block    = row
            var presence = presenceRow
            var columns  = .mcusPerRow
            while columns
            {
                if .restartInterval and .restartsLeft == 0 do
                    try .restartProcess()
                var count = 1
                #static if REFINE
                {
                    if not .decodeBlockAcRefine(block, &presence[0], table, band, bit) do
                        fail InvalidFormatError{"decode error"}
                }
                else
                {
                    if .eobRun
                    {
                        // A run in the first pass touches no coefficients. Consume it up to
                        // the next row or restart marker, whichever comes first.
                        count = Math.min(.eobRun, columns)
                        if .restartInterval do
                            count = Math.min(count, .restartsLeft)
                        .eobRun -= count
                    }
                    else
                    {
                        if not .decodeBlockAcFirst(block, &presence[0], table) do
                            fail InvalidFormatError{"decode error"}
                    }
                }

                .restartsLeft -= count
                columns       -= count
                block         += 64 * count
                presence      += count
            }

            row         += stride
            presenceRow += coefficients.blockNumX
        }
    }

    mtd(Refine: bool) decodeDcScan() fail
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

                if .restartInterval and (.restartsLeft == 0)
                {
                    try .restartProcess()
                }

                for mcuBlock in .blocksPerMcu
                {
                    let componentId = .mcuOrg[mcuBlock]
                    let blkX        = blockMcutX[componentId] + blockMcuOfsX
                    let blkY        = blockMcutY[componentId] + blockMcuOfsY
                    if dcOnlyScan
                    {
                        if refinementScan
                        {
                            try .decodeBlockDcRefine(componentId, blkX, blkY)
                        }
                        else
                        {
                            try .decodeBlockDcFirst(componentId, blkX, blkY)
                        }
                    }
                    else
                    {
                        if refinementScan
                        {
                            try .decodeBlockAcRefine(componentId, blkX, blkY)
                        }
                        else
                        {
                            try .decodeBlockAcFirst(componentId, blkX, blkY)
                        }
                    }

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
        if .spectralStart > .spectralEnd or .spectralEnd > 63
        {
            fail InvalidFormatError{"bad sos spectral"}
        }

        if .spectralStart == 0 ? .spectralEnd != 0 : .compsInScan != 1
        {
            fail InvalidFormatError{"bad sos spectral"}
        }

        if .successiveHigh != 0 and .successiveLow != .successiveHigh - 1
        {
            fail InvalidFormatError{"bad sos successive"}
        }
    }

    mtd initProgressive() fail
    {
        for i in .compsInFrame
        {
            .coefficients[i] = coeffBufOpen(.maxMcusPerRow * .compSampH[i], .maxMcusPerCol * .compSampV[i])
        }

        for
        {
            let res = try .initScan()
            if not res
            {
                break
            }

            let refinementScan = .successiveHigh != 0
            if .spectralStart == 0
            {
                if refinementScan do
                    try .decodeDcScan'true()
                else do
                    try .decodeDcScan'false()
            }
            elif refinementScan
            {
                try .decodeAcScan'true()
            }
            else
            {
                try .decodeAcScan'false()
            }

            .primeMarkerBits()
        }

        if .lastMarkerSynthetic
        {
            fail InvalidFormatError{"JPEG data ends before the end-of-image marker"}
        }

        // The masks have no further use once every scan has been decoded.
        for &component in .coefficients do
            component.nonzeroAc.free()

        // Match the transposed coefficient layout so dequantization can multiply a vector of
        // coefficients at a time.
        for &table in .quant where not table.isEmpty()
        {
            var natural: [64] s16
            for i in 64
            {
                natural[Zag[i]] = table[i]
            }

            Memory.copy(table.storage(), &natural[0], #sizeof(natural))
        }

        .compsInScan = .compsInFrame
        for i in .compsInFrame
        {
            .compList[i] = i
        }

        .calcMcuBlockOrder()
    }
}
