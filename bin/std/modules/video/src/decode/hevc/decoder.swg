//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns decoder state, the decoded picture buffer, reference picture sets, and reference lists.
//
#global namespace Hevc
#global internal

using Core, Core.Errors

// The granularity every per-block grid uses, in luma samples.
//
// Four samples is the smallest block the format gives its own motion, intra mode or coded-block
// flag to, so one grid at that pitch answers every neighbour question the decoding processes ask.
const MinBlockLog2 = 2_u32
const MinBlockSize = 1_u32 << MinBlockLog2

// Prediction modes, clause 7.4.9.5.
const ModeInter = 0_u8
const ModeIntra = 1_u8
const ModeSkip  = 2_u8

// Partition modes, Table 7-10.
const Part2Nx2N = 0_u32
const Part2NxN  = 1_u32
const PartNx2N  = 2_u32
const PartNxN   = 3_u32
const Part2NxnU = 4_u32
const Part2NxnD = 5_u32
const PartnLx2N = 6_u32
const PartnRx2N = 7_u32

// Intra prediction modes, Table 8-1.
const IntraPlanar    = 0_u8
const IntraDc        = 1_u8
const IntraAngular26 = 26_u8
const IntraAngular10 = 10_u8

// The decoded picture buffer never holds more than sixteen pictures plus the one being decoded.
const MaxDpbFrames = 17_u32

// One prediction block's motion, kept for every four-sample block of the current picture.
struct PuMotion
{
    mv:        [2, 2] s16     // [list][component], in quarter luma samples.
    refIdx:    [2] s8 = [-1, -1]
    predFlags: u8     // Bit 0 for list 0, bit 1 for list 1.
}

// The reference pictures one slice predicts from, resolved to entries of the decoded picture
// buffer, clause 8.3.4.
struct RefPicList
{
    frames:   [ListCount, MaxRefPics] (*Frame?)
    poc:      [ListCount, MaxRefPics] s32
    longTerm: [ListCount, MaxRefPics] bool
    count:    [ListCount] u32
}

// One picture in a decoder lane's logical decoded-picture buffer.
//
// The storage can belong to another lane. Marking therefore stays with the lane state while the
// frame carries an atomic hold that prevents its owner from reusing it during reconstruction.
struct DpbReference
{
    frame:   *Frame?
    marking: FrameMarking
}

// Decodes one H.265 stream, one access unit at a time.
//
// The decoder owns its parameter sets and its decoded picture buffer; a caller hands it the
// access units of one stream in decoding order and takes the reconstructed picture of each. It
// never holds the stream: everything it keeps between pictures is the reference state the next
// picture may predict from.
#[Swag.NoCopy]
struct Decoder
{
    sps:       [16] Sps
    pps:       [64] Pps
    activeSps: const *Sps?
    activePps: const *Pps?

    dpb:            [MaxDpbFrames] Frame
    current:        *Frame?
    references:     [MaxDpbFrames] DpbReference
    referenceCount: u32

    // The picture the last slice header closed, for a caller that feeds units one at a time.
    finishedFrame: *Frame?

    header:            SliceHeader
    previousHeader:    SliceHeader
    refList:           RefPicList
    cabac:             CabacReader
    rbsp:              Array!{u8}
    preparedBody:      Array!{u8}
    preparedHeaderBit: u64
    preparedPicture:   bool

    // Wavefront and dependent-slice context storage, clause 9.3.2.4.
    wppState:       CabacState
    dependentState: CabacState

    // Private reconstruction scratch and wake events kept by this frame owner.
    wavefrontWorkers:  [*] Decoder?
    wavefrontEvents:   [*] Sync.Event?
    wavefrontRowCount: u32

    // Picture order count state, clause 8.3.1.
    pocMsb:         s32
    prevPocLsb:     u32
    prevPocMsb:     s32
    pocValue:       s32
    firstPicture:   bool = true
    noRaslOutput:   bool
    raslSuppressed: bool     // The random access point in force drops its skipped leading pictures.

    // Picture geometry, recomputed when a sequence or picture parameter set is activated.
    gridWidth:     u32
    gridHeight:    u32
    zScan:         Array!{u32}
    ctbRsToTs:     Array!{u32}
    ctbTsToRs:     Array!{u32}
    tileId:        Array!{u16}
    ctbSliceAddr:  Array!{u32}
    ctbSliceIndex: Array!{u16}
    sliceParams:   Array!{SliceDeblock}

    // Per-block state of the picture being decoded.
    predMode:   Array!{u8}
    intraModeY: Array!{u8}
    ctDepth:    Array!{u8}
    skipFlag:   Array!{u8}
    qpY:        Array!{s8}
    cbfLuma:    Array!{u8}
    motion:     Array!{PuMotion}
    edgeFlags:  Array!{u8}     // Bit 0 a transform edge, bit 1 a prediction edge.
    // Sample adaptive offset parameters, and the deblocked picture the filter reads.
    sao:              Array!{SaoParameters}
    saoUsed:          bool
    saoSource:        Array!{u16}
    saoSourceChromaB: Array!{u16}
    saoSourceChromaR: Array!{u16}

    // Coefficient and prediction scratch, reused by every transform block.
    coefficients:         [32 * 32] s16
    coefficientRows:      [32] u32     // Significant coefficient rows, one bitset per column.
    coefficientColumns:   u32          // Columns that contain at least one significant coefficient.
    residual:             [32 * 32] s32
    predSamples:          [64 * 64] u16
    predBuffer:           [2, 64 * 64] s16     // Intermediate inter prediction, one per list.
    transformMatrix:      [32 * 32] s16
    transformMatrixReady: bool

    // Slice-scoped decoding state.
    qpYPred:          s32
    sliceAddrRs:      u32
    currentQp:        s32
    qpYPrev:          s32
    isCuQpDeltaCoded: bool
    cuQpDeltaVal:     s32
    ctbAddrTs:        u32
    ctbAddrRs:        u32
    sliceIndex:       u32
}

impl Decoder
{
    mtd opDrop()
    {
        .releaseWavefrontWorkers()
        .releaseReferenceState()
    }

    // Releases every picture the decoder still holds.
    mtd reset()
    {
        .releaseReferenceState()
        for &frame in .dpb
        {
            frame.marking      = .Unused
            frame.outputNeeded = false
        }

        .current      = null
        .activeSps    = null
        .activePps    = null
        .firstPicture = true
        .pocMsb       = 0
        .prevPocLsb   = 0
        .prevPocMsb   = 0
    }

    // Starts from the prediction state published by the preceding frame lane.
    mtd inheritPredictionState(previous: *Decoder)
    {
        .releaseReferenceState()
        for index in previous.referenceCount
        {
            .references[index] = previous.references[index]
            Atomic.add(&.references[index].frame!.reconstructionHolds, 1)
        }

        .referenceCount = previous.referenceCount
        .pocMsb         = previous.pocMsb
        .prevPocLsb     = previous.prevPocLsb
        .prevPocMsb     = previous.prevPocMsb
        .pocValue       = previous.pocValue
        .firstPicture   = previous.firstPicture
        .noRaslOutput   = previous.noRaslOutput
        .raslSuppressed = previous.raslSuppressed
    }

    // Releases the frame storage borrowed by this lane's logical decoded-picture buffer.
    private mtd releaseReferenceState()
    {
        for index in .referenceCount
        {
            let frame = .references[index].frame
            if frame
            {
                Atomic.add(&frame.reconstructionHolds, ~0_u32)
            }

            .references[index] = {}
        }

        .referenceCount = 0
    }

    // Adds a newly started picture to the lane's decoded-picture buffer.
    mtd holdReference(frame: *Frame, marking: FrameMarking) fail
    {
        if .referenceCount >= MaxDpbFrames
        {
            fail InvalidFormatError{"HEVC decoded picture buffer holds too many pictures"}
        }

        .references[.referenceCount] = {frame, marking}
        .referenceCount += 1
        Atomic.add(&frame.reconstructionHolds, 1)
    }

    // Returns the sequence parameter set the active picture parameter set names.
    mtd const sequenceOf(pps: const *Pps)->const *Sps?
    {
        if pps.spsId >= 16 or not .sps[pps.spsId].valid
        {
            return null
        }

        return &.sps[pps.spsId]
    }

    // Reads one parameter set, and activates nothing: activation happens at the first slice.
    mtd readParameterSet(nalType: u32, payload: const [..] u8) fail
    {
        unescapeRbsp(&.rbsp, payload)
        var reader: BitReader
        reader.init(.rbsp.toSlice())

        switch nalType
        {
        case NalSps:

            // The identifier sits after the profile structure, so the set is parsed into a
            // scratch value and only stored once its identifier is known.
            var parsed: Sps
            try parsed.read(&reader)
            var identifierReader: BitReader
            identifierReader.init(.rbsp.toSlice())
            discard identifierReader.read(4)
            let maxSubLayersMinus1 = identifierReader.read(3)
            discard identifierReader.bit()
            try readProfileTierLevel(&identifierReader, maxSubLayersMinus1)
            let identifier = identifierReader.ue()
            if identifier >= 16
            {
                fail InvalidFormatError{"HEVC sequence parameter set identifier is out of range"}
            }

            .sps[identifier] = parsed

        case NalPps:
            let identifier = reader.ue()
            if identifier >= 64
            {
                fail InvalidFormatError{"HEVC picture parameter set identifier is out of range"}
            }

            let sequenceId = reader.ue()
            if sequenceId >= 16 or not .sps[sequenceId].valid
            {
                fail InvalidFormatError{"HEVC picture parameter set names a sequence that was not received"}
            }

            var restart: BitReader
            restart.init(.rbsp.toSlice())
            discard restart.ue()
            try .pps[identifier].read(&restart, &.sps[sequenceId])
        }
    }

    // Rebuilds the scan and availability tables of a newly activated picture parameter set.
    mtd activate(sps: const *Sps, pps: const *Pps) fail
    {
        if not .transformMatrixReady
        {
            for basis in 32_u32
            {
                for sample in 32_u32
                {
                    .transformMatrix[basis * 32 + sample] = TransMatrix32[basis, sample]
                }
            }

            .transformMatrixReady = true
        }

        if .activeSps == sps and .activePps == pps
        {
            return
        }

        .activeSps = sps
        .activePps = pps

        let ctbSize      = sps.sizeInCtbs
        let blocksPerCtb = 1_u32 << (sps.ctbLog2Size - MinBlockLog2)
        .gridWidth  = sps.widthInCtbs * blocksPerCtb
        .gridHeight = sps.heightInCtbs * blocksPerCtb

        .ctbRsToTs.resize(cast(u64, ctbSize))
        .ctbTsToRs.resize(cast(u64, ctbSize))
        .tileId.resize(cast(u64, ctbSize))
        .ctbSliceAddr.resize(cast(u64, ctbSize))
        try .buildTileScan(sps, pps)

        let blocks = cast(u64, .gridWidth) * cast(u64, .gridHeight)
        .zScan.resize(blocks)
        .buildZScan(sps)

        .predMode.resize(blocks)
        .intraModeY.resize(blocks)
        .ctDepth.resize(blocks)
        .skipFlag.resize(blocks)
        .qpY.resize(blocks)
        .cbfLuma.resize(blocks)
        .motion.resize(blocks)
        .edgeFlags.resize(blocks)
    }

    // Builds the raster-to-tile scan conversion of clause 6.5.1.
    private mtd buildTileScan(sps: const *Sps, pps: const *Pps) fail
    {
        var colWidth, rowHeight: [33] u32
        for index in pps.numTileColumns
        {
            colWidth[index] = pps.colBoundary[index + 1] - pps.colBoundary[index]
        }

        for index in pps.numTileRows
        {
            rowHeight[index] = pps.rowBoundary[index + 1] - pps.rowBoundary[index]
        }

        for addressRs in sps.sizeInCtbs
        {
            let tbX = addressRs % sps.widthInCtbs
            let tbY = addressRs / sps.widthInCtbs

            var tileX, tileY = 0_u32
            for index in pps.numTileColumns where tbX >= pps.colBoundary[index]
            {
                tileX = index
            }

            for index in pps.numTileRows where tbY >= pps.rowBoundary[index]
            {
                tileY = index
            }

            var address = 0_u32
            for index in tileX
            {
                address += rowHeight[tileY] * colWidth[index]
            }

            for index in tileY
            {
                address += sps.widthInCtbs * rowHeight[index]
            }

            address += (tbY - pps.rowBoundary[tileY]) * colWidth[tileX] + tbX - pps.colBoundary[tileX]

            if address >= sps.sizeInCtbs
            {
                fail InvalidFormatError{"HEVC tile geometry does not cover the picture exactly"}
            }

            .ctbRsToTs[addressRs] = address
            .ctbTsToRs[address]   = addressRs
        }

        var tileIndex = 0_u32
        for row in pps.numTileRows
        {
            for column in pps.numTileColumns
            {
                for y in pps.rowBoundary[row] until pps.rowBoundary[row + 1]
                {
                    for x in pps.colBoundary[column] until pps.colBoundary[column + 1]
                    {
                        .tileId[.ctbRsToTs[y * sps.widthInCtbs + x]] = cast(u16, tileIndex)
                    }
                }

                tileIndex += 1
            }
        }
    }

    // Builds the z-scan order array of clause 6.5.2.
    private mtd buildZScan(sps: const *Sps)
    {
        let depth = sps.ctbLog2Size - MinBlockLog2
        for y in .gridHeight
        {
            for x in .gridWidth
            {
                let ctbX    = (x << MinBlockLog2) >> sps.ctbLog2Size
                let ctbY    = (y << MinBlockLog2) >> sps.ctbLog2Size
                var address = .ctbRsToTs[ctbY * sps.widthInCtbs + ctbX] << (depth * 2)
                for bit in depth
                {
                    let mask = 1_u32 << bit
                    if mask & x
                    {
                        address += mask * mask
                    }

                    if mask & y
                    {
                        address += 2 * mask * mask
                    }
                }

                .zScan[cast(u64, y) * cast(u64, .gridWidth) + cast(u64, x)] = address
            }
        }
    }

    // Returns the index of the four-sample block covering luma sample `(x, y)`.
    #[Swag.Inline]
    mtd const blockIndex(x, y: s32)->u64 => cast(u64, (y >> MinBlockLog2)) * cast(u64, .gridWidth) + cast(u64, (x >> MinBlockLog2))

    // Reports whether the block covering `(xNb, yNb)` may be predicted from, clause 6.4.1.
    mtd const isAvailable(xCurr, yCurr, xNb, yNb: s32)->bool
    {
        let sps = unwrap .activeSps
        if xNb < 0 or yNb < 0 or xNb >= cast(s32, sps.width) or yNb >= cast(s32, sps.height)
        {
            return false
        }

        let currentZ   = .zScan[.blockIndex(xCurr, yCurr)]
        let neighbourZ = .zScan[.blockIndex(xNb, yNb)]
        if neighbourZ > currentZ
        {
            return false
        }

        let currentCtb   = .ctbRsToTs[.ctbAddressRs(xCurr, yCurr)]
        let neighbourCtb = .ctbRsToTs[.ctbAddressRs(xNb, yNb)]
        if .tileId[currentCtb] != .tileId[neighbourCtb]
        {
            return false
        }

        return .ctbSliceAddr[.ctbAddressRs(xCurr, yCurr)] == .ctbSliceAddr[.ctbAddressRs(xNb, yNb)]
    }

    // Reports whether the block covering `(xNb, yNb)` may be predicted from and is not intra,
    // which is what prediction block availability adds, clause 6.4.2.
    mtd const isAvailablePrediction(xCb, yCb: s32, nCbS: s32, xPb, yPb, nPbW, nPbH: s32, partIdx: u32, xNb, yNb: s32)->bool
    {
        let sameCb = xCb <= xNb and yCb <= yNb and xCb + nCbS > xNb and yCb + nCbS > yNb

        var available: bool
        if not sameCb
        {
            available = .isAvailable(xPb, yPb, xNb, yNb)
        }
        else
        {
            // The second partition of a two-part coding unit may not predict from the first when
            // that would make the two identical.
            let secondOfPair = (nPbW << 1) == nCbS and (nPbH << 1) == nCbS and partIdx == 1
            available = not (secondOfPair and yCb + nPbH <= yNb and xCb + nPbW > xNb)
        }

        if available and .predMode[.blockIndex(xNb, yNb)] == ModeIntra
        {
            available = false
        }

        return available
    }

    #[Swag.Inline]
    mtd const ctbAddressRs(x, y: s32)->u64
    {
        let sps = unwrap .activeSps
        return cast(u64, (cast(u32, y) >> sps.ctbLog2Size)) * cast(u64, sps.widthInCtbs) + cast(u64, (cast(u32, x) >> sps.ctbLog2Size))
    }

    // Computes the picture order count of the picture starting here, clause 8.3.1.
    mtd updatePictureOrder(nalType, temporalId, pocLsb: u32, sps: const *Sps)
    {
        if isIdrNal(nalType)
        {
            .pocMsb   = 0
            .pocValue = 0
        }
        else
        {
            .computePictureOrder(nalType, pocLsb, sps)
        }

        if isReferenceNal(nalType) and temporalId == 0
        {
            .prevPocLsb = pocLsb
            .prevPocMsb = .pocMsb
        }
    }

    private mtd computePictureOrder(nalType, pocLsb: u32, sps: const *Sps)
    {
        let maxPocLsb = 1_u32 << sps.log2MaxPocLsb
        if isIrapNal(nalType) and .noRaslOutput
        {
            .pocMsb = 0
        }
        else
        {
            let lsb  = pocLsb
            let half = maxPocLsb / 2
            if lsb < .prevPocLsb and .prevPocLsb - lsb >= half
            {
                .pocMsb = .prevPocMsb + cast(s32, maxPocLsb)
            }
            else if lsb > .prevPocLsb and lsb - .prevPocLsb > half
            {
                .pocMsb = .prevPocMsb - cast(s32, maxPocLsb)
            }
            else
            {
                .pocMsb = .prevPocMsb
            }
        }

        .pocValue = .pocMsb + cast(s32, pocLsb)
    }

    // Finds a decoded picture by its order count.
    mtd findByPoc(poc: s32, shortTerm: bool)->*Frame?
    {
        for index in .referenceCount
        {
            let reference = &.references[index]
            let frame     = unwrap reference.frame
            if frame.poc != poc
            {
                continue
            }

            if shortTerm and reference.marking != .ShortTerm
            {
                continue
            }

            return frame
        }

        return null
    }

    // Finds a long-term picture by the low bits of its order count.
    mtd findByPocLsb(pocLsb: u32, mask: u32)->*Frame?
    {
        for index in .referenceCount
        {
            let frame = unwrap .references[index].frame
            if (cast(u32, frame.poc) & mask) == pocLsb
            {
                return frame
            }
        }

        return null
    }

    // Takes a free picture out of the decoded picture buffer.
    mtd acquireFrame()->*Frame?
    {
        for &frame in .dpb
        {
            if Atomic.get(&frame.reconstructionHolds) == 0 and Atomic.get(&frame.heldByCaller) == 0
            {
                return frame
            }
        }

        return null
    }

    // Applies the reference picture set of the current slice, clause 8.3.2.
    //
    // Every picture the set does not name stops being a reference. The set is stated relative to
    // the current picture's order count, so it has to be resolved after the count is known.
    mtd applyReferencePictureSet(header: const *SliceHeader, sps: const *Sps) fail
    {
        var stCurrBefore, stCurrAfter, stFoll: [MaxRefPics] s32
        var ltCurr, ltFoll: [MaxRefPics] s32
        var beforeCount, afterCount, follCount = 0_u32
        var ltCurrCount, ltFollCount = 0_u32

        let rps = header.activeRps(sps)
        for index in rps.negativeCount
        {
            let poc = .pocValue + rps.negativeDelta[index]
            if rps.negativeUsed[index]
            {
                stCurrBefore[beforeCount] = poc
                beforeCount += 1
            }
            else
            {
                stFoll[follCount] = poc
                follCount         += 1
            }
        }

        for index in rps.positiveCount
        {
            let poc = .pocValue + rps.positiveDelta[index]
            if rps.positiveUsed[index]
            {
                stCurrAfter[afterCount] = poc
                afterCount += 1
            }
            else
            {
                stFoll[follCount] = poc
                follCount         += 1
            }
        }

        let maxPocLsb = 1_u32 << sps.log2MaxPocLsb
        for index in header.numLongTermSps + header.numLongTermPics
        {
            var poc = cast(s32, header.ltPocLsb[index])
            if header.ltMsbPresent[index]
            {
                poc = .pocValue - cast(s32, (header.ltMsbCycle[index] * maxPocLsb)) - (.pocValue & cast(s32, (maxPocLsb - 1))) + cast(s32, header.ltPocLsb[index])
            }

            if header.ltUsedByCurr[index]
            {
                ltCurr[ltCurrCount] = poc
                ltCurrCount         += 1
            }
            else
            {
                ltFoll[ltFollCount] = poc
                ltFollCount         += 1
            }
        }

        // Mark first, so a picture named by the set keeps its marking whatever order it is in.
        var keep: [MaxDpbFrames] bool
        for index in .referenceCount
        {
            let reference = &.references[index]
            let frame     = unwrap reference.frame
            if frame == .current
            {
                continue
            }

            var named = false
            for entry in beforeCount where frame.poc == stCurrBefore[entry]
            {
                named = true
            }

            for entry in afterCount where frame.poc == stCurrAfter[entry]
            {
                named = true
            }

            for entry in follCount where frame.poc == stFoll[entry]
            {
                named = true
            }

            if named
            {
                reference.marking = .ShortTerm
                keep[index]       = true
                continue
            }

            let mask = maxPocLsb - 1
            for entry in ltCurrCount where (cast(u32, frame.poc) & mask) == (cast(u32, ltCurr[entry]) & mask)
            {
                named = true
            }

            for entry in ltFollCount where (cast(u32, frame.poc) & mask) == (cast(u32, ltFoll[entry]) & mask)
            {
                named = true
            }

            if named
            {
                reference.marking = .LongTerm
                keep[index]       = true
            }
        }

        var index = 0_u32
        while index < .referenceCount
        {
            let frame = unwrap .references[index].frame
            if frame != .current and not keep[index]
            {
                Atomic.add(&frame.reconstructionHolds, ~0_u32)
                .referenceCount    -= 1
                .references[index] = .references[.referenceCount]
                .references[.referenceCount] = {}
                keep[index]        = keep[.referenceCount]
                continue
            }

            index += 1
        }

        // Build the two current sets in the order clause 8.3.4 consumes them.
        .refList.count[0] = 0
        .refList.count[1] = 0
        try .buildLists(header, stCurrBefore[0 until beforeCount], stCurrAfter[0 until afterCount], ltCurr[0 until ltCurrCount], maxPocLsb - 1)
    }

    // Builds the reference picture lists of clause 8.3.4.
    private mtd buildLists(header: const *SliceHeader, before, after, longTerm: const [..] s32, lsbMask: u32) fail
    {
        if header.sliceType == SliceTypeI
        {
            return
        }

        var temp:      [ListCount, 3 * MaxRefPics] (*Frame?)
        var tempPoc:   [ListCount, 3 * MaxRefPics] s32
        var tempLong:  [ListCount, 3 * MaxRefPics] bool
        var tempCount: [ListCount] u32

        let totalCurr = cast(u32, (before.count + after.count + longTerm.count))
        if not totalCurr
        {
            fail InvalidFormatError{"HEVC predicted slice has no reference picture available"}
        }

        for list in (header.sliceType == SliceTypeB ? 2_u32 : 1_u32)
        {
            let needed = Math.max(header.numRefIdx[list], totalCurr)
            let first  = list == 0 ? before : after
            let second = list == 0 ? after : before
            while tempCount[list] < needed
            {
                for poc in first
                {
                    if tempCount[list] >= needed
                    {
                        break
                    }

                    temp[list, tempCount[list]]     = .findByPoc(poc, shortTerm: true)
                    tempPoc[list, tempCount[list]]  = poc
                    tempLong[list, tempCount[list]] = false
                    tempCount[list] += 1
                }

                for poc in second
                {
                    if tempCount[list] >= needed
                    {
                        break
                    }

                    temp[list, tempCount[list]]     = .findByPoc(poc, shortTerm: true)
                    tempPoc[list, tempCount[list]]  = poc
                    tempLong[list, tempCount[list]] = false
                    tempCount[list] += 1
                }

                for poc in longTerm
                {
                    if tempCount[list] >= needed
                    {
                        break
                    }

                    temp[list, tempCount[list]]     = .findByPocLsb(cast(u32, poc) & lsbMask, lsbMask)
                    tempPoc[list, tempCount[list]]  = poc
                    tempLong[list, tempCount[list]] = true
                    tempCount[list] += 1
                }
            }

            for index in header.numRefIdx[list]
            {
                let source = header.listModification[list] ? header.listEntry[list, index] : index
                if source >= tempCount[list]
                {
                    fail InvalidFormatError{"HEVC reference list modification is out of range"}
                }

                // A reference the stream names but the buffer never received is replaced by the
                // nearest picture available, which keeps a stream that starts mid-sequence
                // decodable instead of failing on its first predicted picture.
                var frame = temp[list, source]
                if not frame
                {
                    frame = .nearestReference(tempPoc[list, source])
                }

                if not frame
                {
                    fail InvalidFormatError{"HEVC slice refers to a picture that was never decoded"}
                }

                .refList.frames[list, index]   = frame
                .refList.poc[list, index]      = tempPoc[list, source]
                .refList.longTerm[list, index] = tempLong[list, source]
            }

            .refList.count[list] = header.numRefIdx[list]
        }
    }

    // Returns the decoded picture closest in order count to `poc`, for a missing reference.
    private mtd nearestReference(poc: s32)->*Frame?
    {
        var best: *Frame?
        var bestDistance = Swag.S32.Max
        for index in .referenceCount
        {
            let frame = unwrap .references[index].frame
            if frame == .current
            {
                continue
            }

            let distance = Math.abs(frame.poc - poc)
            if distance < bestDistance
            {
                bestDistance = distance
                best         = frame
            }
        }

        return best
    }
}
