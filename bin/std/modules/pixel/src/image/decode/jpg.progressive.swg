#global namespace Jpg

using Swag, Core, Core.Errors

impl Decoder
{
    func coeffBufOpen(blkNumX, blkNumY, blkLenX, blkLenY: s32)->CoeffBuf
    {
        with var result: retval
        {
            .blockNumX = blkNumX
            .blockNumY = blkNumY
            .blockLenX = blkLenX
            .blockLenY = blkLenY
            .blockSize = (blkLenX * blkLenY) * #sizeof(s16)
            .pdata.resize(cast(u64) .blockSize * blkNumX * blkNumY)
        }

        return result
    }

    mtd decodeBlockDcFirst(cmpId: u32, blkX, blkY: s32) fail
    {
        var p = coeffBufGetp(.dcCoeffs[cmpId], blkX, blkY)
        var s = .huffDecode(&.h[.compDcTab[cmpId]])
        if s != 0
        {
            s = extendSign(.getBits2(s), s)
        }

        s                 += .lastDcVal[cmpId]
        .lastDcVal[cmpId] = s
        p[0]              = cast(s16) (s << .successiveLow)
    }

    mtd decodeBlockDcRefine(cmpId: u32, blkX, blkY: s32) fail
    {
        if .getBits2(1)
        {
            var p = coeffBufGetp(.dcCoeffs[cmpId], blkX, blkY)
            p[0] |= (1's16 << .successiveLow)
        }
    }

    mtd decodeBlockAcFirst(cmpId: u32, blkX, blkY: s32) fail
    {
        if .eobRun
        {
            .eobRun -= 1
            return
        }

        var p = coeffBufGetp(.acCoeffs[cmpId], blkX, blkY)

        for var k = .spectralStart; k <= .spectralEnd; k += 1
        {
            var s = .huffDecode(&.h[.compAcTab[cmpId]])
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

                s         = extendSign(rbits, s)
                p[Zag[k]] = cast(s16) (s << .successiveLow)
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
    }

    mtd decodeBlockAcRefine(cmpId: u32, blkX, blkY: s32) fail
    {
        let p1 = 1 << .successiveLow
        let m1 = -1 << .successiveLow
        var p  = coeffBufGetp(.acCoeffs[cmpId], blkX, blkY)
        var k  = .spectralStart
        if .eobRun == 0
        {
            if .spectralEnd >= 64 do
                fail InvalidFormatError{"decode error"}

            while k <= .spectralEnd
            {
                var s = .huffDecode(&.h[.compAcTab[cmpId]])
                var r = s >> 4
                s &= 15

                if s
                {
                    if s != 1 do
                        fail InvalidFormatError{"decode error"}
                    if .getBits2(1) do
                        s = p1
                    else do
                        s = m1
                }
                else
                {
                    if r != 15
                    {
                        .eobRun = 1 << r
                        if r do
                            .eobRun += .getBits2(r)
                        break
                    }
                }

                for
                {
                    var thisCoef = p + Zag[k]
                    if dref thisCoef != 0
                    {
                        if .getBits2(1)
                        {
                            if (dref thisCoef & cast(s16) p1) == 0
                            {
                                if dref thisCoef >= 0 do
                                    dref thisCoef += cast(s16) p1
                                else do
                                    dref thisCoef += cast(s16) m1
                            }
                        }
                    }
                    else
                    {
                        r -= 1
                        if r < 0 do
                            break
                    }

                    k += 1
                    if k > .spectralEnd do
                        break
                }

                if s and (k < 64)
                {
                    p[Zag[k]] = cast(s16) s
                }

                k += 1
            }
        }

        if .eobRun > 0
        {
            if .spectralEnd >= 64 do
                fail InvalidFormatError{"decode error"}
            while k <= .spectralEnd
            {
                var thisCoef = p + Zag[k]
                if dref thisCoef != 0
                {
                    if .getBits2(1)
                    {
                        if (dref thisCoef & cast(s16) p1) == 0
                        {
                            if dref thisCoef >= 0 do
                                dref thisCoef += cast(s16) p1
                            else do
                                dref thisCoef += cast(s16) m1
                        }
                    }
                }

                k += 1
            }

            .eobRun -= 1
        }
    }

    mtd decodeScan(dcOnlyScan, refinementScan: bool) fail
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
                    .restartProcess()

                for mcuBlock in .blocksPerMcu
                {
                    let componentId = .mcuOrg[mcuBlock]
                    let blkX        = blockMcutX[componentId] + blockMcuOfsX
                    let blkY        = blockMcutY[componentId] + blockMcuOfsY
                    if dcOnlyScan
                    {
                        if refinementScan do
                            .decodeBlockDcRefine(componentId, blkX, blkY)
                        else do
                            .decodeBlockDcFirst(componentId, blkX, blkY)
                    }
                    else
                    {
                        if refinementScan do
                            .decodeBlockAcRefine(componentId, blkX, blkY)
                        else do
                            .decodeBlockAcFirst(componentId, blkX, blkY)
                    }

                    if .compsInScan == 1 do
                        blockMcutX[componentId] += 1
                    else
                    {
                        blockMcuOfsX += 1
                        if blockMcuOfsX == .compSampH[componentId]
                        {
                            blockMcuOfsX = 0
                            blockMcuOfsY += 1
                            if blockMcuOfsY == .compSampV[componentId]
                            {
                                blockMcuOfsY            = 0
                                blockMcutX[componentId] += .compSampH[componentId]
                            }
                        }
                    }
                }

                .restartsLeft -= 1
            }

            if .compsInScan == 1 do
                blockMcutY[.compList[0]] += 1
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

    mtd initProgressive() fail
    {
        if .compsInFrame == 4 do
            fail UnsupportedFormatError{"unsupported color space"}

        for i in .compsInFrame
        {
            .dcCoeffs[i] = coeffBufOpen(.maxMcusPerRow * .compSampH[i], .maxMcusPerCol * .compSampV[i], 1, 1)
            .acCoeffs[i] = coeffBufOpen(.maxMcusPerRow * .compSampH[i], .maxMcusPerCol * .compSampV[i], 8, 8)
        }

        for
        {
            let res = .initScan()
            if !res do
                break

            let dcOnlyScan     = (.spectralStart == 0)
            let refinementScan = (.successiveHigh != 0)

            if (.spectralStart > .spectralEnd) or (.spectralEnd > 63) do
                fail InvalidFormatError{"bad sos spectral"}

            if dcOnlyScan
            {
                if .spectralEnd do
                    fail InvalidFormatError{"bad sos spectral"}
            }
            elif .compsInScan != 1
            {
                fail InvalidFormatError{"bad sos spectral"}
            }

            if refinementScan and (.successiveLow != .successiveHigh - 1) do
                fail InvalidFormatError{"bad sos successive"}

            .decodeScan(dcOnlyScan, refinementScan)

            .bitsLeft = 16

            .getBits1(16)
            .getBits1(16)
        }

        .compsInScan = .compsInFrame
        for i in .compsInFrame do
            .compList[i] = i
        .calcMcuBlockOrder()
    }
}
