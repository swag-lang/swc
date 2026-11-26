//! Format: Joint Photographic Experts Group (JPEG) decoder component.
//! Supported: Baseline and progressive Huffman-coded grayscale, YCbCr, directly sampled RGB, and CMYK or YCCK images.
//! Not supported: Arithmetic coding, lossless JPEG, and unsupported chroma sampling layouts.
//! Role: This file owns scan parsing, entropy decode, sampling, and color conversion.
//
#global namespace Jpg

using Swag, Core, Core.Errors

impl Decoder
{
    func coeffBufGetp(cb: CoeffBuf, blkX, blkY: s32)->[*] s16
    {
        Swag.assert(blkX < cb.blockNumX)
        Swag.assert(blkY < cb.blockNumY)
        let block = cast(u64, blkY) * cast(u64, cb.blockNumX) + cast(u64, blkX)
        return cb.values.storage() + block * 64
    }

    mtd loadNextRow() fail
    {
        var blockMcuX: [MaxComponents] s32

        var p = cast([*] s16, .quantBuf.storage())
        for .mcusPerRow
        {
            var blockMcuOfsX = 0
            var blockMcuOfsY = 0
            for mcuBlock in .blocksPerMcu
            {
                let componentId = .mcuOrg[mcuBlock]
                let q           = .quant[.compQuant[componentId]].storage()
                let samples     = coeffBufGetp(.coefficients[componentId], blockMcuX[componentId] + blockMcuOfsX, .blockMcuY[componentId] + blockMcuOfsY)
                for row in 8
                {
                    let offset       = row * 8
                    let weights      = Math.Simd.load(q + offset)
                    let coefficients = Math.Simd.load(samples + offset)
                    Math.Simd.store(p + offset, coefficients * weights)
                }

                p += 64
                if .compsInScan == 1
                {
                    blockMcuX[componentId] += 1
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
                            blockMcuX[componentId] += .compSampH[componentId]
                        }
                    }
                }
            }
        }

        if .compsInScan == 1
        {
            .blockMcuY[.compList[0]] += 1
        }
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
        if c != (.nextRestartNum + cast(u32, Marker.M_RST0)) do
            fail InvalidFormatError{"bad restart marker"}

        Memory.clear(&.lastDcVal, cast(u64, .compsInFrame) * #sizeof(u32))

        .eobRun         = 0
        .restartsLeft   = .restartInterval
        .nextRestartNum = (.nextRestartNum + 1) & 7
        .bitsLeft       = 16

        .getBits2(16)
        .getBits2(16)
    }

    #[Swag.Inline]
    mtd huffDecode(ph: *HuffTables)->s32
    {
        // A short code carries its own length in the look-ahead table.
        let symbol = ph.lookUp[(.bitBuf >> 8) & 0xFF]
        if symbol < 0 do
            return .decodeLongHuffCode(ph, symbol)

        .getBits2(symbol >> 8)
        return symbol & 0xFF
    }

    #[Swag.NoInline]
    private mtd decodeLongHuffCode(ph: *HuffTables, prefix: s32)->s32
    {
        .getBits2(8)
        var symbol = prefix
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
        let missing = .maxBlocksPerRow - .mcusPerRow * cast(s32, .blocksPerMcu)
        if missing < 0 do
            fail InvalidFormatError{"decode error"}

        var coefficients: [64] s16
        let p      = cast([*] s16, &coefficients[0])
        var sample = .safeSampleBuf()
        for .mcusPerRow
        {
            if .restartInterval and (.restartsLeft == 0) do
                try .restartProcess()

            for mcuBlock in .blocksPerMcu
            {
                let block      = &.baselineBlocks[mcuBlock]
                let q          = unwrap block.quant
                let previousDc = unwrap block.previousDc

                var s = .huffDecode(unwrap block.dc)
                if s != 0
                {
                    s = extendSign(.getBits2(s), s)
                }

                s += previousDc[]
                previousDc[] = s

                p[0] = cast(s16, (s * q[0]))
                let ph = unwrap block.ac

                var k  = 1
                var ac = 0's16
                while k < 64
                {
                    let entry = ph.lookUp[(.bitBuf >> 8) & 0xFF]
                    var run, amplitude: s32
                    if entry >= 1 << 24
                    {
                        // This prefix includes both the code and the amplitude bits.
                        .getBits2(entry >> 24)
                        run       = (entry >> 4) & 0x0F
                        amplitude = (entry << 8) >> 24
                    }
                    else
                    {
                        if entry < 0
                        {
                            s = .decodeLongHuffCode(ph, entry)
                        }
                        else
                        {
                            .getBits2(entry >> 8)
                            s = entry & 0xFF
                        }

                        run = s >> 4
                        s   &= 0x0F
                        if not s
                        {
                            if run != 15 do
                                break
                            if k + 15 > 63 do
                                fail InvalidFormatError{"decode error"}
                            k += 16
                            continue
                        }

                        amplitude = extendSign(.getBits2(s), s)
                    }

                    k += run
                    if k > 63 do
                        fail InvalidFormatError{"decode error"}
                    let value = cast(s16, (amplitude * q[k]))
                    p[Zag[k]] = value
                    ac        |= value
                    k         += 1
                }

                // Keep the current coefficients hot and reuse their storage for the next block.
                if ac
                {
                    idctFull(p, sample)
                    Memory.clear(p, 64'u64 * #sizeof(s16))
                }
                else
                {
                    idctFlat(p[0], sample)
                }

                sample += 64
            }

            .restartsLeft -= 1
        }

        // Blocks omitted by a partial scan had zero coefficients in the row buffer.
        if missing do
            Memory.set(sample, 128, cast(u64, missing) * 64)
    }

    mtd decodeScanLine(destination: [*] u8? = null)->[*] u8 fail
    {
        if .mcuLinesLeft == 0
        {
            if .progressiveFlag
            {
                try .loadNextRow()
                .transformProgressiveRow()
            }
            else
            {
                try .decodeNextRow()
            }

            if .totalLinesLeft <= .maxMcuSizeY do
                try .findEoi()
            .mcuLinesLeft = .maxMcuSizeY
        }

        let first  = destination orelse .scanLine0.storage()
        var output = first
        switch .scanType
        {
        case YH2V2, YH1V2:
            if (.mcuLinesLeft & 1) == 0
            {
                let second = destination and .totalLinesLeft > 1 ?
                             first - cast(u64, .realDestBytesPerScanLine) : .scanLine1.storage()
                if .scanType == YH2V2 do
                    .convertH2V2(first, second)
                else do
                    .convertH1V2(first, second)
            }
            else
            {
                output = destination orelse .scanLine1.storage()
            }

        case YH2V1:
            .convertH2V1(first)

        case YH1V1:
            .convertH1V1(first)

        case RGBH1V1:
            .convertRgbH1V1(first)

        case CmykH1V1:
            .convertCmykH1V1(first)

        case YGeneric:
            .convertGeneric(first)

        case GrayScale:
            .convertGrayscale(first)
        }

        .mcuLinesLeft   -= 1
        .totalLinesLeft -= 1
        return output
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
                            (not .hasAdobeMarker and not .hasJfifMarker and .compIdent[0] == 'R' and .compIdent[1] == 'G' and .compIdent[2] == 'B')
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
                if (.compSampH[0] == 1) and
                   (.compSampH[1] == 1) and
                   (.compSampH[2] == 1) and
                   (.compSampV[1] == .compSampV[0]) and
                   (.compSampV[2] == .compSampV[0])
                {
                    .scanType        = YH1V1
                    .maxBlocksPerMcu = 3 * .compSampV[0]
                    .maxMcuSizeX     = 8
                    .maxMcuSizeY     = 8 * .compSampV[0]
                }
                elif (.compSampH[0] == 2) and
                     (.compSampH[1] == 1) and
                     (.compSampH[2] == 1) and
                     (.compSampV[1] == .compSampV[0]) and
                     (.compSampV[2] == .compSampV[0])
                {
                    // Some encoders group two vertical block rows without subsampling them.
                    .scanType        = YH2V1
                    .maxBlocksPerMcu = 4 * .compSampV[0]
                    .maxMcuSizeX     = 16
                    .maxMcuSizeY     = 8 * .compSampV[0]
                }
                elif (.compSampH[0] == 1) and
                     (.compSampV[0] == 2) and
                     (.compSampH[1] == 1) and
                     (.compSampV[1] == 1) and
                     (.compSampH[2] == 1) and
                     (.compSampV[2] == 1)
                {
                    .scanType        = YH1V2
                    .maxBlocksPerMcu = 4
                    .maxMcuSizeX     = 8
                    .maxMcuSizeY     = 16
                }
                elif (.compSampH[0] == 2) and
                     (.compSampV[0] == 2) and
                     (.compSampH[1] == 1) and
                     (.compSampV[1] == 1) and
                     (.compSampH[2] == 1) and
                     (.compSampV[2] == 1)
                {
                    .scanType        = YH2V2
                    .maxBlocksPerMcu = 6
                    .maxMcuSizeX     = 16
                    .maxMcuSizeY     = 16
                }
                else
                {
                    let maxSamplingH = Math.max(.compSampH[0], .compSampH[1], .compSampH[2])
                    let maxSamplingV = Math.max(.compSampV[0], .compSampV[1], .compSampV[2])
                    for component in 3
                    {
                        if maxSamplingH % .compSampH[component] or maxSamplingV % .compSampV[component] do
                            fail UnsupportedFormatError{"JPEG component sampling ratios must divide the MCU sampling grid"}
                        .maxBlocksPerMcu += .compSampH[component] * .compSampV[component]
                    }

                    .scanType    = YGeneric
                    .maxMcuSizeX = maxSamplingH * 8
                    .maxMcuSizeY = maxSamplingV * 8
                }
            }
        }
        elif .compsInFrame == 4
        {
            // Four components are the inks of a printed page, written either as they are or with
            // their three chromatic channels carried the way luma and chroma are. Neither form
            // subsamples in practice, and the layout that does is well formed and simply not read
            // here.
            for i in 4
            {
                if .compSampH[i] != 1 or .compSampV[i] != 1 do
                    fail UnsupportedFormatError{Errors.mkString(Format.toString("JPEG four-component sampling of %x% is not supported", .compSampH[i], .compSampV[i]))}
            }

            .scanType        = CmykH1V1
            .maxBlocksPerMcu = 4
            .maxMcuSizeX     = 8
            .maxMcuSizeY     = 8
        }
        else
        {
            fail UnsupportedFormatError{"unsupported color space"}
        }

        if .maxBlocksPerMcu > MaxBlocksPerMcu do
            fail UnsupportedFormatError{"JPEG MCU has too many blocks"}

        .maxMcusPerRow = (.imageSizeX + (.maxMcuSizeX - 1)) / .maxMcuSizeX
        .maxMcusPerCol = (.imageSizeY + (.maxMcuSizeY - 1)) / .maxMcuSizeY

        if .scanType == GrayScale do
            .destBytesPerPixel = 1
        else do
            .destBytesPerPixel = 3

        // Conversion writes whole MCUs, including padding at the right edge.
        .destBytesPerScanLine     = .maxMcusPerRow * .maxMcuSizeX * .destBytesPerPixel
        .realDestBytesPerScanLine = (.imageSizeX * .destBytesPerPixel)

        .maxBlocksPerRow = .maxMcusPerRow * .maxBlocksPerMcu
        .totalLinesLeft  = .imageSizeY
        .mcuLinesLeft    = 0
        if not .decOptions.decodePixels do
            return

        .scanLine0.resize(cast(u64, .destBytesPerScanLine) + 8)
        let scanLine0 = .scanLine0.storage()
        Memory.clear(scanLine0, cast(u64, .destBytesPerScanLine))

        .scanLine1.resize(cast(u64, .destBytesPerScanLine) + 8)
        let scanLine1 = .scanLine1.storage()
        Memory.clear(scanLine1, cast(u64, .destBytesPerScanLine))

        if .progressiveFlag do
            .quantBuf.resize(cast(u64, .maxBlocksPerRow) * 64 * #sizeof(s16) + 8)

        // The conversions read whole vectors, so the last sample of a row is followed by enough
        // slack for a sixteen-byte read that starts on it.
        .sampleBuf.resize(cast(u64, .maxBlocksPerRow) * 64 + 64)
        .pSampleBuf = .sampleBuf.buffer
    }

    mtd initScan()->bool fail
    {
        let res = try .locateSosMarker()
        if not res do
            return false

        if .progressiveFlag do
            try .validateProgressiveScan()
        .calcMcuBlockOrder()
        try .checkHuffTables()
        try .checkQuantTables()

        if not .progressiveFlag and .decOptions.decodePixels
        {
            for index in .blocksPerMcu
            {
                let component = .mcuOrg[index]
                .baselineBlocks[index] = BaselineBlock{
                    dc: &.h[.compDcTab[component]],
                    ac: &.h[.compAcTab[component]],
                    quant: .quant[.compQuant[component]].storage(),
                    previousDc: &.lastDcVal[component]}
            }
        }

        Memory.clear(.lastDcVal, cast(u64, .compsInFrame) * #sizeof(u32))

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
        let inBufOfs = unwrap .inBufOfs
        inBufOfs[] = q
        .inBufLeft += 1
    }

    mtd fixInBuffer()
    {
        if .bitsLeft == 16 do
            .stuffChar(cast(u8, ((.bitBuf >> 16) & 0xFF)))
        if .bitsLeft >= 8 do
            .stuffChar(cast(u8, ((.bitBuf >> 24) & 0xFF)))

        .stuffChar(cast(u8, (.bitBuf & 0xFF)))
        .stuffChar(cast(u8, ((.bitBuf >> 8) & 0xFF)))
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

        var p = 0
        let huffNumBuf = .huffNum[idx].storage()
        for l in 1 to 16
        {
            for var i = 1; i <= huffNumBuf[l]; i += 1
            {
                huffSize[p] = cast(u8, l)
                p += 1
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

        let packAmplitude = idx >= MaxHuffTables / 2 and not .progressiveFlag and .decOptions.decodePixels
        var nextFreeEntry = -1
        let huffValBuf    = .huffVal[idx].storage()
        p = 0
        while p < lastp
        {
            let i = huffValBuf[p]
            cde = huffCode[p]
            let codeSize = huffSize[p]
            if codeSize <= 8
            {
                cde <<= (8 - codeSize)
                let entry         = (cast(s32, codeSize) << 8) | cast(s32, i)
                let amplitudeSize = cast(s32, (i & 0x0F))
                let totalSize     = cast(s32, codeSize) + amplitudeSize
                if packAmplitude and amplitudeSize and totalSize <= 8
                {
                    let amplitudeMask = (1 << amplitudeSize) - 1
                    for 1 << (8 - codeSize)
                    {
                        let amplitudeBits = cast(u32, ((cde >> (8 - totalSize)) & amplitudeMask))
                        let amplitude     = extendSign(amplitudeBits, amplitudeSize)
                        hs.lookUp[cde] = entry | ((amplitude & 0xFF) << 16) | (totalSize << 24)
                        cde += 1
                    }
                }
                else
                {
                    for 1 << (8 - codeSize)
                    {
                        hs.lookUp[cde] = entry
                        cde += 1
                    }
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
                        currentEntry  = nextFreeEntry
                        nextFreeEntry -= 2
                    }
                    else
                    {
                        currentEntry = hs.tree[-currentEntry - 1]
                    }

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

        // Header-only probes validate the referenced tables but do not consume entropy codes.
        if not .decOptions.decodePixels and (not .progressiveFlag or not .decOptions.decodeMetadata) do
            return

        for i in MaxHuffTables where .huffNum[i].count and not .h[i].ready
        {
            .makeHuffTable(i, &.h[i])
            .h[i].ready = true
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
                let cid       = .compList[cNum]
                var numBlocks = .compSampH[cid] * .compSampV[cid]
                while numBlocks
                {
                    .mcuOrg[.blocksPerMcu] = cid
                    .blocksPerMcu += 1
                    numBlocks     -= 1
                }
            }
        }
    }

    mtd initFirstScan() fail
    {
        let res = try .initScan()
        if not res do
            fail InvalidFormatError{"unexpected marker"}
    }
}
