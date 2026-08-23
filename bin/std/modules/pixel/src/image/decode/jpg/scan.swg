#global namespace Jpg

using Swag, Core, Core.Errors

impl Decoder
{
    func coeffBufGetp(cb: CoeffBuf, blkX, blkY: s32)->[*] s16
    {
        Debug.assert(blkX < cb.blockNumX)
        Debug.assert(blkY < cb.blockNumY)
        return cast([*] s16) (cast([*] u8) cb.pdata.buffer! + blkX * cb.blockSize + blkY * (cb.blockSize * cb.blockNumX))
    }

    mtd loadNextRow() fail
    {
        var blockMcuX: [MaxComponents] s32

        var rowBlock = 0'u32
        for .mcusPerRow
        {
            var blockMcuOfsX = 0
            var blockMcuOfsY = 0
            for mcuBlock in .blocksPerMcu
            {
                let componentId = .mcuOrg[mcuBlock]

                var p   = .blockSeg[rowBlock]!
                let q   = .quant[.compQuant[componentId]].buffer!
                var pAC = coeffBufGetp(.acCoeffs[componentId], blockMcuX[componentId] + blockMcuOfsX, .blockMcuY[componentId] + blockMcuOfsY)
                let pDC = coeffBufGetp(.dcCoeffs[componentId], blockMcuX[componentId] + blockMcuOfsX, .blockMcuY[componentId] + blockMcuOfsY)

                p[0] = pDC[0]
                Memory.copy(&p[1], &pAC[1], 63'u64 * #sizeof(s16))

                var i = 63
                while i > 0
                {
                    if p[Zag[cast(u32) i]] do
                        break
                    i -= 1
                }

                while i >= 0
                {
                    if p[Zag[cast(u32) i]] do
                        p[Zag[cast(u32) i]] *= q[cast(u32) i]
                    i -= 1
                }

                rowBlock += 1
                if .compsInScan == 1 do
                    blockMcuX[componentId] += 1
                else
                {
                    blockMcuOfsX += 1
                    if blockMcuOfsX == .compSampH[componentId]
                    {
                        blockMcuOfsX = 0
                        blockMcuOfsY += 1
                        if blockMcuOfsY == .compSampV[componentId]
                        {
                            blockMcuOfsY           = 0
                            blockMcuX[componentId] += .compSampH[componentId]
                        }
                    }
                }
            }
        }

        if .compsInScan == 1 do
            .blockMcuY[.compList[0]] += 1
        else
        {
            for componentNum in .compsInScan
            {
                let componentId = .compList[componentNum]
                .blockMcuY[componentId] += .compSampV[componentId]
            }
        }
    }

    mtd restartProcess() fail
    {
        var i = 1536
        while i > 0
        {
            if .getChar() == 0xFF do
                break
            i -= 1
        }

        if i == 0 do
            fail InvalidFormatError{"bad restart marker"}

        var c = 0
        while i > 0
        {
            c = .getChar()
            if c != 0xFF do
                break
            i -= 1
        }

        if i == 0 do
            fail InvalidFormatError{"bad restart marker"}
        if c != (.nextRestartNum + cast(u32) Marker.M_RST0) do
            fail InvalidFormatError{"bad restart marker"}

        Memory.clear(&.lastDcVal, cast(u64) .compsInFrame * #sizeof(u32))

        .eobRun         = 0
        .restartsLeft   = .restartInterval
        .nextRestartNum = (.nextRestartNum + 1) & 7
        .bitsLeft       = 16

        .getBits2(16)
        .getBits2(16)
    }

    mtd huffDecode(ph: *HuffTables)->s32
    {
        // A code of eight bits or less is fully described by the entry the next eight bits select:
        // it carries its own length, so the symbol costs one load.
        var symbol = ph.lookUp[(.bitBuf >> 8) & 0xFF]
        if symbol >= 0
        {
            .getBits2(symbol >> 8)
            return symbol & 0xFF
        }

        .getBits2(8)
        for
        {
            symbol = ph.tree[~symbol + (1 - .getBits2(1))]
            if symbol >= 0 do
                break
        }

        return symbol
    }

    mtd decodeNextRow() fail
    {
        var rowBlock = 0
        for .mcusPerRow
        {
            if .restartInterval and (.restartsLeft == 0) do
                .restartProcess()

            for mcuBlock in .blocksPerMcu
            {
                let componentId = .mcuOrg[mcuBlock]
                var p           = .blockSeg[rowBlock]!
                let q           = .quant[.compQuant[componentId]].buffer!

                var s = .huffDecode(&.h[.compDcTab[componentId]])
                if s != 0
                {
                    s = extendSign(.getBits2(s), s)
                }

                s += .lastDcVal[componentId]
                .lastDcVal[componentId] = s

                p[0] = cast(s16) (s * q[0])
                let ph = &.h[.compAcTab[componentId]]

                var k = 1
                while k < 64
                {
                    s = .huffDecode(ph)
                    var r = s >> 4
                    s &= 0x0F

                    if s
                    {
                        if r
                        {
                            if (k + r) > 63 do
                                fail InvalidFormatError{"decode error"}
                            k += r
                        }

                        let rbits = .getBits2(s)
                        if s > 15 do
                            fail InvalidFormatError{"decode error"}

                        s         = extendSign(rbits, s)
                        p[Zag[k]] = cast(s16) (s * q[k])
                    }
                    else
                    {
                        if r == 15
                        {
                            if (k + 15) > 63 do
                                fail InvalidFormatError{"decode error"}
                            k += 15
                        }
                        else
                        {
                            break
                        }
                    }

                    k += 1
                }

                rowBlock += 1
            }

            .restartsLeft -= 1
        }
    }

    mtd decode(scanLineOfs: *#null *void, scanLineLen: *u32)->s32 fail
    {
        if .totalLinesLeft == 0 do
            return Done

        if .mcuLinesLeft == 0
        {
            if .progressiveFlag do
                .loadNextRow()
            else do
                .decodeNextRow()
            if .totalLinesLeft <= .maxMcuSizeY do
                .findEoi()
            .transformRow()
            .mcuLinesLeft = .maxMcuSizeY
        }

        switch .scanType
        {
        case YH2V2:
            if (.mcuLinesLeft & 1) == 0
            {
                .convertH2V2()
                scanLineOfs[] = .scanLine0.buffer
            }
            else do
                scanLineOfs[] = .scanLine1.buffer

        case YH2V1:
            .convertH2V1()
            scanLineOfs[] = .scanLine0.buffer

        case YH1V2:
            if (.mcuLinesLeft & 1) == 0
            {
                .convertH1V2()
                scanLineOfs[] = .scanLine0.buffer
            }
            else do
                scanLineOfs[] = .scanLine1.buffer

        case YH1V1:
            .convertH1V1()
            scanLineOfs[] = .scanLine0.buffer

        case RGBH1V1:
            .convertRgbH1V1()
            scanLineOfs[] = .scanLine0.buffer

        case GrayScale:
            .convertGrayscale()
            scanLineOfs[] = .scanLine0.buffer
        }

        scanLineLen[]   = .realDestBytesPerScanLine
        .mcuLinesLeft   -= 1
        .totalLinesLeft -= 1

        return Okay
    }

    mtd initFrame() fail
    {
        if .compsInFrame == 1
        {
            .scanType        = GrayScale
            .maxBlocksPerMcu = 1
            .maxMcuSizeX     = 8
            .maxMcuSizeY     = 8
        }
        elif .compsInFrame == 3
        {
            let directRgb = (.hasAdobeMarker and .adobeTransform == 0) or
                            (!.hasAdobeMarker and !.hasJfifMarker and .compIdent[0] == 'R' and .compIdent[1] == 'G' and .compIdent[2] == 'B')
            if directRgb
            {
                for i in 3
                {
                    if .compSampH[i] != 1 or .compSampV[i] != 1 do
                        fail UnsupportedFormatError{"JPEG direct RGB only supports 1x1 component sampling"}
                }

                .scanType        = RGBH1V1
                .maxBlocksPerMcu = 3
                .maxMcuSizeX     = 8
                .maxMcuSizeY     = 8
            }
            else
            {
                // The decoder reads the four layouts a chroma plane of one block per minimum
                // coded unit describes, which is every subsampling in common use. A frame whose
                // chroma samples more than that is well formed, and simply not read here.
                if (.compSampH[1] != 1) or (.compSampV[1] != 1) or (.compSampH[2] != 1) or (.compSampV[2] != 1) do
                    fail UnsupportedFormatError{Errors.mkString(Format.toString("JPEG chroma sampling of %x% is not supported", .compSampH[1], .compSampV[1]))}

                if (.compSampH[0] == 1) and (.compSampV[0] == 1)
                {
                    .scanType        = YH1V1
                    .maxBlocksPerMcu = 3
                    .maxMcuSizeX     = 8
                    .maxMcuSizeY     = 8
                }
                elif (.compSampH[0] == 2) and (.compSampV[0] == 1)
                {
                    .scanType        = YH2V1
                    .maxBlocksPerMcu = 4
                    .maxMcuSizeX     = 16
                    .maxMcuSizeY     = 8
                }
                elif (.compSampH[0] == 1) and (.compSampV[0] == 2)
                {
                    .scanType        = YH1V2
                    .maxBlocksPerMcu = 4
                    .maxMcuSizeX     = 8
                    .maxMcuSizeY     = 16
                }
                elif (.compSampH[0] == 2) and (.compSampV[0] == 2)
                {
                    .scanType        = YH2V2
                    .maxBlocksPerMcu = 6
                    .maxMcuSizeX     = 16
                    .maxMcuSizeY     = 16
                }
                else do
                    fail InvalidFormatError{"invalid samp factors"}
            }
        }
        else do
            fail UnsupportedFormatError{"unsupported color space"}

        .maxMcusPerRow = (.imageSizeX + (.maxMcuSizeX - 1)) / .maxMcuSizeX
        .maxMcusPerCol = (.imageSizeY + (.maxMcuSizeY - 1)) / .maxMcuSizeY

        if .scanType == GrayScale do
            .destBytesPerPixel = 1
        else do
            .destBytesPerPixel = 4

        .destBytesPerScanLine     = ((.imageSizeX + 15) & 0xFFF0) * .destBytesPerPixel
        .realDestBytesPerScanLine = (.imageSizeX * .destBytesPerPixel)

        .scanLine0.resize(cast(u64) .destBytesPerScanLine + 8)
        let scanLine0 = .scanLine0.buffer!
        Memory.clear(scanLine0, cast(u64) .destBytesPerScanLine)

        .scanLine1.resize(cast(u64) .destBytesPerScanLine + 8)
        let scanLine1 = .scanLine1.buffer!
        Memory.clear(scanLine1, cast(u64) .destBytesPerScanLine)

        .maxBlocksPerRow = .maxMcusPerRow * .maxBlocksPerMcu
        if .maxBlocksPerRow > MaxBlocksPerRow do
            fail InvalidFormatError{"assertion error"}

        .quantBuf.resize(cast(u64) .maxBlocksPerRow * 64 * #sizeof(s16) + 8)
        Memory.clear(.quantBuf.buffer!, .quantBuf.count)
        for i in .maxBlocksPerRow
        {
            .blockSeg[i] = cast([*] s16) (cast([*] u8) .quantBuf.buffer! + i * 64 * #sizeof(s16))
        }

        // The conversions read whole vectors, so the last sample of a row is followed by enough
        // slack for a sixteen-byte read that starts on it.
        .sampleBuf.resize(cast(u64) .maxBlocksPerRow * 64 + 64)
        .pSampleBuf = .sampleBuf.buffer

        .totalLinesLeft = .imageSizeY
        .mcuLinesLeft   = 0
    }

    mtd initScan()->bool fail
    {
        let res = .locateSosMarker()
        if !res do
            return false

        .calcMcuBlockOrder()
        .checkHuffTables()
        .checkQuantTables()

        Memory.clear(.lastDcVal, cast(u64) .compsInFrame * #sizeof(u32))

        .eobRun = 0
        if .restartInterval
        {
            .restartsLeft   = .restartInterval
            .nextRestartNum = 0
        }

        .fixInBuffer()
        return true
    }

    mtd stuffChar(q: u8)
    {
        .inBufOfs -= 1
        let inBufOfs = .inBufOfs!
        inBufOfs[] = q
        .inBufLeft += 1
    }

    mtd fixInBuffer()
    {
        if .bitsLeft == 16 do
            .stuffChar(cast(u8) ((.bitBuf >> 16) & 0xFF))
        if .bitsLeft >= 8 do
            .stuffChar(cast(u8) ((.bitBuf >> 24) & 0xFF))

        .stuffChar(cast(u8) (.bitBuf & 0xFF))
        .stuffChar(cast(u8) ((.bitBuf >> 8) & 0xFF))
        .bitsLeft = 16

        .getBits2(16)
        .getBits2(16)
    }

    mtd checkQuantTables() fail
    {
        for i in .compsInScan
        {
            if .quant[.compQuant[.compList[i]]].isEmpty() do
                fail InvalidFormatError{"undefined quant table"}
        }
    }

    mtd makeHuffTable(idx: s32, hs: *HuffTables)
    {
        var huffSize: [257] u8
        var huffCode: [257] u32

        var p          = 0
        let huffNumBuf = .huffNum[idx].buffer!
        for l in 1 to 16
        {
            for var i = 1; i <= huffNumBuf[l]; i += 1
            {
                huffSize[p] = cast(u8) l
                p           += 1
            }
        }

        huffSize[p] = 0
        let lastp = p
        var cde   = 0
        var si    = huffSize[0]
        p = 0

        while huffSize[p]
        {
            while huffSize[p] == si
            {
                huffCode[p] = cde
                p, cde      += 1
            }

            cde <<= 1
            si  += 1
        }

        Memory.clear(hs.tree, #sizeof(hs.tree))

        // A prefix that no code covers only appears in a malformed stream. Reading it as a
        // one-bit symbol keeps the scan moving, where an entry consuming no bit would not.
        for i in 256 do
            hs.lookUp[i] = 1 << 8

        var nextFreeEntry = -1
        let huffValBuf    = .huffVal[idx].buffer!
        p = 0
        while p < lastp
        {
            let i = huffValBuf[p]
            cde = huffCode[p]
            let codeSize = huffSize[p]
            if codeSize <= 8
            {
                cde <<= (8 - codeSize)
                let entry = (cast(s32) codeSize << 8) | cast(s32) i
                for var l = 1 << (8 - codeSize); l > 0; l -= 1
                {
                    hs.lookUp[cde] = entry
                    cde            += 1
                }
            }
            else
            {
                // A long code reaches a subtree instead, and a subtree entry is the only negative
                // value a prefix can hold: anything else means the slot is still free.
                let subtree      = (cde >> (codeSize - 8)) & 0xFF
                var currentEntry = hs.lookUp[subtree]
                if currentEntry >= 0
                {
                    hs.lookUp[subtree] = nextFreeEntry
                    currentEntry       = nextFreeEntry
                    nextFreeEntry      -= 2
                }

                cde <<= (16 - (codeSize - 8))
                for var l = codeSize; l > 9; l -= 1
                {
                    if (cde & 0x8000) == 0 do
                        currentEntry -= 1

                    if hs.tree[-currentEntry - 1] == 0
                    {
                        hs.tree[-currentEntry - 1] = nextFreeEntry
                        currentEntry               = nextFreeEntry
                        nextFreeEntry              -= 2
                    }
                    else do
                        currentEntry = hs.tree[-currentEntry - 1]

                    cde <<= 1
                }

                if (cde & 0x8000) == 0 do
                    currentEntry -= 1
                hs.tree[-currentEntry - 1] = i
            }

            p += 1
        }
    }

    mtd checkHuffTables() fail
    {
        // An abbreviated stream defines no entropy coding of its own and relies on the tables of
        // the specification, which is exactly how a camera writes the Motion JPEG frames of a
        // recording.
        if .hasNoHuffTable() do
            .installDefaultHuffTables()

        for i in .compsInScan
        {
            if (.spectralStart == 0) and (.huffNum[.compDcTab[.compList[i]]].isEmpty()) do
                fail InvalidFormatError{"undefined huff table"}

            if (.spectralEnd > 0) and (.huffNum[.compAcTab[.compList[i]]].isEmpty()) do
                fail InvalidFormatError{"undefined huff table"}
        }

        for i in MaxHuffTables
        {
            if .huffNum[i].count
            {
                .makeHuffTable(i, &.h[i])
            }
        }

        for i in .blocksPerMcu
        {
            .dcHuffSeg[i] = &.h[.compDcTab[.mcuOrg[i]]]
            .acHuffSeg[i] = &.h[.compAcTab[.mcuOrg[i]]]
            .component[i] = cast(*u32) &.lastDcVal[.mcuOrg[i]]
        }
    }

    mtd calcMcuBlockOrder()
    {
        var maxSampH = 1
        var maxSampV = 1

        for cid in .compsInFrame
        {
            maxSampH = Math.max(maxSampH, .compSampH[cid])
            maxSampV = Math.max(maxSampV, .compSampV[cid])
        }

        for cid in .compsInFrame
        {
            .compBlocksH[cid] = ((((.imageSizeX * .compSampH[cid]) + (maxSampH - 1)) / maxSampH) + 7) / 8
            .compBlocksV[cid] = ((((.imageSizeY * .compSampV[cid]) + (maxSampV - 1)) / maxSampV) + 7) / 8
        }

        if .compsInScan == 1
        {
            .mcusPerRow = .compBlocksH[.compList[0]]
            .mcusPerCol = .compBlocksV[.compList[0]]
        }
        else
        {
            .mcusPerRow = (((.imageSizeX + 7) / 8) + (maxSampH - 1)) / maxSampH
            .mcusPerCol = (((.imageSizeY + 7) / 8) + (maxSampV - 1)) / maxSampV
        }

        if .compsInScan == 1
        {
            .mcuOrg[0]    = .compList[0]
            .blocksPerMcu = 1
        }
        else
        {
            .blocksPerMcu = 0
            for cNum in .compsInScan
            {
                let cid        = .compList[cNum]
                var num_blocks = .compSampH[cid] * .compSampV[cid]
                while num_blocks
                {
                    .mcuOrg[.blocksPerMcu] = cid
                    .blocksPerMcu          += 1
                    num_blocks             -= 1
                }
            }
        }
    }

    mtd initSequential() fail
    {
        let res = .initScan()
        if !res do
            fail InvalidFormatError{"unexpected marker"}
    }
}
