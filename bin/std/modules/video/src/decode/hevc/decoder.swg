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
const MinBlockLog2 = 2'u32
const MinBlockSize = 1'u32 << MinBlockLog2

// Prediction modes, clause 7.4.9.5.
const ModeInter = 0'u8
const ModeIntra = 1'u8
const ModeSkip  = 2'u8

// Partition modes, Table 7-10.
const Part2Nx2N = 0'u32
const Part2NxN  = 1'u32
const PartNx2N  = 2'u32
const PartNxN   = 3'u32
const Part2NxnU = 4'u32
const Part2NxnD = 5'u32
const PartnLx2N = 6'u32
const PartnRx2N = 7'u32

// Intra prediction modes, Table 8-1.
const IntraPlanar    = 0'u8
const IntraDc        = 1'u8
const IntraAngular26 = 26'u8
const IntraAngular10 = 10'u8

// The decoded picture buffer never holds more than sixteen pictures plus the one being decoded.
const MaxDpbFrames = 17'u32

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
    frames:   [ListCount, MaxRefPics] #null *Frame
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
    frame:   #null *Frame
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
    activeSps: #null const *Sps
    activePps: #null const *Pps

    dpb:            [MaxDpbFrames] Frame
    current:        #null *Frame
    references:     [MaxDpbFrames] DpbReference
    referenceCount: u32

    // The picture the last slice header closed, for a caller that feeds units one at a time.
    finishedFrame: #null *Frame

    header:            SliceHeader
    previousHeader:    SliceHeader
    refList:           RefPicList
    cabac:             CabacReader
    rbsp:              Array'u8
    preparedBody:      Array'u8
    preparedHeaderBit: u64
    preparedPicture:   bool

    // Wavefront and dependent-slice context storage, clause 9.3.2.4.
    wppState:       CabacState
    dependentState: CabacState

    // Picture order count state, clause 8.3.1.
    pocMsb:       s32
    prevPocLsb:   u32
    prevPocMsb:   s32
    pocValue:     s32
    firstPicture: bool = true
    noRaslOutput: bool

    // Picture geometry, recomputed when a sequence or picture parameter set is activated.
    gridWidth:     u32
    gridHeight:    u32
    zScan:         Array'u32
    ctbRsToTs:     Array'u32
    ctbTsToRs:     Array'u32
    tileId:        Array'u16
    ctbSliceAddr:  Array'u32
    ctbSliceIndex: Array'u16
    sliceParams:   Array'SliceDeblock

    // Per-block state of the picture being decoded.
    predMode:   Array'u8
    intraModeY: Array'u8
    ctDepth:    Array'u8
    skipFlag:   Array'u8
    qpY:        Array's8
    cbfLuma:    Array'u8
    motion:     Array'PuMotion
    edgeFlags:  Array'u8     // Bit 0 a transform edge, bit 1 a prediction edge.
    // Sample adaptive offset parameters, and the deblocked picture the filter reads.
    sao:              Array'SaoParameters
    saoUsed:          bool
    saoSource:        Array'u16
    saoSourceChromaB: Array'u16
    saoSourceChromaR: Array'u16

    // Coefficient and prediction scratch, reused by every transform block.
    coefficients: [32 * 32] s16
    coefficientRows: [32] u32     // Significant coefficient rows, one bitset per column.
    coefficientColumns: u32       // Columns that contain at least one significant coefficient.
    residual:     [32 * 32] s32
    predSamples:  [64 * 64] u16
    predBuffer:   [2, 64 * 64] s16     // Intermediate inter prediction, one per list.
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
    }

    // Releases the frame storage borrowed by this lane's logical decoded-picture buffer.
    private mtd releaseReferenceState()
    {
        for index in .referenceCount
        {
            let frame = .references[index].frame
            if frame do
                Atomic.add(&frame!.reconstructionHolds, ~0'u32)
            .references[index] = {}
        }

        .referenceCount = 0
    }

    // Adds a newly started picture to the lane's decoded-picture buffer.
    mtd holdReference(frame: *Frame, marking: FrameMarking) fail
    {
        if .referenceCount >= MaxDpbFrames do
            fail InvalidFormatError{"HEVC decoded picture buffer holds too many pictures"}
        .references[.referenceCount] = {frame, marking}
        .referenceCount              += 1
        Atomic.add(&frame.reconstructionHolds, 1)
    }

    // Returns the sequence parameter set the active picture parameter set names.
    mtd const sequenceOf(pps: const *Pps)->#null const *Sps
    {
        if pps.spsId >= 16 or !.sps[pps.spsId].valid do
            return null
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
            if identifier >= 16 do
                fail InvalidFormatError{"HEVC sequence parameter set identifier is out of range"}
            .sps[identifier] = parsed

        case NalPps:
            let identifier = reader.ue()
            if identifier >= 64 do
                fail InvalidFormatError{"HEVC picture parameter set identifier is out of range"}
            let sequenceId = reader.ue()
            if sequenceId >= 16 or !.sps[sequenceId].valid do
                fail InvalidFormatError{"HEVC picture parameter set names a sequence that was not received"}

            var restart: BitReader
            restart.init(.rbsp.toSlice())
            discard restart.ue()
            try .pps[identifier].read(&restart, &.sps[sequenceId])
        }
    }

    // Rebuilds the scan and availability tables of a newly activated picture parameter set.
    mtd activate(sps: const *Sps, pps: const *Pps) fail
    {
        if !.transformMatrixReady
        {
            for basis in 32'u32
            {
                for sample in 32'u32 do
                    .transformMatrix[basis * 32 + sample] = TransMatrix32[basis, sample]
            }
            .transformMatrixReady = true
        }

        if .activeSps == sps and .activePps == pps do
            return

        .activeSps = sps
        .activePps = pps

        let ctbSize      = sps.sizeInCtbs
        let blocksPerCtb = 1'u32 << (sps.ctbLog2Size - MinBlockLog2)
        .gridWidth  = sps.widthInCtbs * blocksPerCtb
        .gridHeight = sps.heightInCtbs * blocksPerCtb

        .ctbRsToTs.resize(cast(u64) ctbSize)
        .ctbTsToRs.resize(cast(u64) ctbSize)
        .tileId.resize(cast(u64) ctbSize)
        .ctbSliceAddr.resize(cast(u64) ctbSize)
        try .buildTileScan(sps, pps)

        let blocks = cast(u64) .gridWidth * cast(u64) .gridHeight
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
        for index in pps.numTileColumns do
            colWidth[index] = pps.colBoundary[index + 1] - pps.colBoundary[index]
        for index in pps.numTileRows do
            rowHeight[index] = pps.rowBoundary[index + 1] - pps.rowBoundary[index]

        for addressRs in sps.sizeInCtbs
        {
            let tbX = addressRs % sps.widthInCtbs
            let tbY = addressRs / sps.widthInCtbs

            var tileX, tileY = 0'u32
            for index in pps.numTileColumns where tbX >= pps.colBoundary[index] do
                tileX = index
            for index in pps.numTileRows where tbY >= pps.rowBoundary[index] do
                tileY = index

            var address = 0'u32
            for index in tileX do
                address += rowHeight[tileY] * colWidth[index]
            for index in tileY do
                address += sps.widthInCtbs * rowHeight[index]
            address += (tbY - pps.rowBoundary[tileY]) * colWidth[tileX] + tbX - pps.colBoundary[tileX]

            if address >= sps.sizeInCtbs do
                fail InvalidFormatError{"HEVC tile geometry does not cover the picture exactly"}
            .ctbRsToTs[addressRs] = address
            .ctbTsToRs[address]   = addressRs
        }

        var tileIndex = 0'u32
        for row in pps.numTileRows
        {
            for column in pps.numTileColumns
            {
                for y in pps.rowBoundary[row] until pps.rowBoundary[row + 1]
                {
                    for x in pps.colBoundary[column] until pps.colBoundary[column + 1] do
                        .tileId[.ctbRsToTs[y * sps.widthInCtbs + x]] = cast(u16) tileIndex
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
                    let mask = 1'u32 << bit
                    if mask & x do
                        address += mask * mask
                    if mask & y do
                        address += 2 * mask * mask
                }

                .zScan[cast(u64) y * cast(u64) .gridWidth + cast(u64) x] = address
            }
        }
    }

    // Returns the index of the four-sample block covering luma sample `(x, y)`.
    #[Swag.Inline]
    mtd const blockIndex(x, y: s32)->u64 => (cast(u64) (y >> MinBlockLog2)) * cast(u64) .gridWidth + cast(u64) (x >> MinBlockLog2)

    // Reports whether the block covering `(xNb, yNb)` may be predicted from, clause 6.4.1.
    mtd const isAvailable(xCurr, yCurr, xNb, yNb: s32)->bool
    {
        let sps = .activeSps!
        if xNb < 0 or yNb < 0 or xNb >= cast(s32) sps.width or yNb >= cast(s32) sps.height do
            return false

        let currentZ   = .zScan[.blockIndex(xCurr, yCurr)]
        let neighbourZ = .zScan[.blockIndex(xNb, yNb)]
        if neighbourZ > currentZ do
            return false

        let currentCtb   = .ctbRsToTs[.ctbAddressRs(xCurr, yCurr)]
        let neighbourCtb = .ctbRsToTs[.ctbAddressRs(xNb, yNb)]
        if .tileId[currentCtb] != .tileId[neighbourCtb] do
            return false
        return .ctbSliceAddr[.ctbAddressRs(xCurr, yCurr)] == .ctbSliceAddr[.ctbAddressRs(xNb, yNb)]
    }

    // Reports whether the block covering `(xNb, yNb)` may be predicted from and is not intra,
    // which is what prediction block availability adds, clause 6.4.2.
    mtd const isAvailablePrediction(xCb, yCb: s32, nCbS: s32, xPb, yPb, nPbW, nPbH: s32, partIdx: u32, xNb, yNb: s32)->bool
    {
        let sameCb = xCb <= xNb and yCb <= yNb and xCb + nCbS > xNb and yCb + nCbS > yNb

        var available: bool
        if !sameCb
        {
            available = .isAvailable(xPb, yPb, xNb, yNb)
        }
        else
        {
            // The second partition of a two-part coding unit may not predict from the first when
            // that would make the two identical.
            let secondOfPair = (nPbW << 1) == nCbS and (nPbH << 1) == nCbS and partIdx == 1
            available = !(secondOfPair and yCb + nPbH <= yNb and xCb + nPbW > xNb)
        }

        if available and .predMode[.blockIndex(xNb, yNb)] == ModeIntra do
            available = false
        return available
    }

    #[Swag.Inline]
    mtd const ctbAddressRs(x, y: s32)->u64
    {
        let sps = .activeSps!
        return (cast(u64) (cast(u32) y >> sps.ctbLog2Size)) * cast(u64) sps.widthInCtbs + cast(u64) (cast(u32) x >> sps.ctbLog2Size)
    }

    // Computes the picture order count of the picture starting here, clause 8.3.1.
    mtd computePoc(nalType: u32, header: const *SliceHeader, sps: const *Sps)
    {
        if isIdrNal(nalType)
        {
            .pocMsb   = 0
            .pocValue = 0
            return
        }

        let maxPocLsb = 1'u32 << sps.log2MaxPocLsb
        if isIrapNal(nalType) and .noRaslOutput
        {
            .pocMsb = 0
        }
        else
        {
            let lsb  = header.pocLsb
            let half = maxPocLsb / 2
            if lsb < .prevPocLsb and .prevPocLsb - lsb >= half do
                .pocMsb = .prevPocMsb + cast(s32) maxPocLsb
            elif lsb > .prevPocLsb and lsb - .prevPocLsb > half do
                .pocMsb = .prevPocMsb - cast(s32) maxPocLsb
            else do
                .pocMsb = .prevPocMsb
        }

        .pocValue = .pocMsb + cast(s32) header.pocLsb
    }

    // Finds a decoded picture by its order count.
    mtd findByPoc(poc: s32, shortTerm: bool)->#null *Frame
    {
        for index in .referenceCount
        {
            let reference = &.references[index]
            let frame     = reference.frame!
            if frame.poc != poc do
                continue
            if shortTerm and reference.marking != .ShortTerm do
                continue
            return frame
        }

        return null
    }

    // Finds a long-term picture by the low bits of its order count.
    mtd findByPocLsb(pocLsb: u32, mask: u32)->#null *Frame
    {
        for index in .referenceCount
        {
            let frame = .references[index].frame!
            if (cast(u32) frame.poc & mask) == pocLsb do
                return frame
        }

        return null
    }

    // Takes a free picture out of the decoded picture buffer.
    mtd acquireFrame()->#null *Frame
    {
        for &frame in .dpb
        {
            if Atomic.get(&frame.reconstructionHolds) == 0 and Atomic.get(&frame.heldByCaller) == 0 do
                return frame
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
        var beforeCount, afterCount, follCount = 0'u32
        var ltCurrCount, ltFollCount           = 0'u32

        let rps = header.activeRps(sps)
        for index in rps.negativeCount
        {
            let poc = .pocValue + rps.negativeDelta[index]
            if rps.negativeUsed[index]
            {
                stCurrBefore[beforeCount] = poc
                beforeCount               += 1
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
                afterCount              += 1
            }
            else
            {
                stFoll[follCount] = poc
                follCount         += 1
            }
        }

        let maxPocLsb = 1'u32 << sps.log2MaxPocLsb
        for index in header.numLongTermSps + header.numLongTermPics
        {
            var poc = cast(s32) header.ltPocLsb[index]
            if header.ltMsbPresent[index] do
                poc = .pocValue - cast(s32) (header.ltMsbCycle[index] * maxPocLsb) - (.pocValue & cast(s32) (maxPocLsb - 1)) + cast(s32) header.ltPocLsb[index]

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
            let frame     = reference.frame!
            if frame == .current do
                continue

            var named = false
            for entry in beforeCount where frame.poc == stCurrBefore[entry] do
                named = true
            for entry in afterCount where frame.poc == stCurrAfter[entry] do
                named = true
            for entry in follCount where frame.poc == stFoll[entry] do
                named = true
            if named
            {
                reference.marking = .ShortTerm
                keep[index]       = true
                continue
            }

            let mask = maxPocLsb - 1
            for entry in ltCurrCount where (cast(u32) frame.poc & mask) == (cast(u32) ltCurr[entry] & mask) do
                named = true
            for entry in ltFollCount where (cast(u32) frame.poc & mask) == (cast(u32) ltFoll[entry] & mask) do
                named = true
            if named
            {
                reference.marking = .LongTerm
                keep[index]       = true
            }
        }

        var index = 0'u32
        while index < .referenceCount
        {
            let frame = .references[index].frame!
            if frame != .current and !keep[index]
            {
                Atomic.add(&frame.reconstructionHolds, ~0'u32)
                .referenceCount              -= 1
                .references[index]           = .references[.referenceCount]
                .references[.referenceCount] = {}
                keep[index]                  = keep[.referenceCount]
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
        if header.sliceType == SliceTypeI do
            return

        var temp:      [ListCount, 3 * MaxRefPics] #null *Frame
        var tempPoc:   [ListCount, 3 * MaxRefPics] s32
        var tempLong:  [ListCount, 3 * MaxRefPics] bool
        var tempCount: [ListCount] u32

        let totalCurr = cast(u32) (@countof(before) + @countof(after) + @countof(longTerm))
        if !totalCurr do
            fail InvalidFormatError{"HEVC predicted slice has no reference picture available"}

        for list in (header.sliceType == SliceTypeB ? 2'u32 : 1'u32)
        {
            let needed = Math.max(header.numRefIdx[list], totalCurr)
            let first  = list == 0 ? before : after
            let second = list == 0 ? after : before
            while tempCount[list] < needed
            {
                for poc in first
                {
                    if tempCount[list] >= needed do
                        break
                    temp[list, tempCount[list]]     = .findByPoc(poc, shortTerm: true)
                    tempPoc[list, tempCount[list]]  = poc
                    tempLong[list, tempCount[list]] = false
                    tempCount[list]                 += 1
                }

                for poc in second
                {
                    if tempCount[list] >= needed do
                        break
                    temp[list, tempCount[list]]     = .findByPoc(poc, shortTerm: true)
                    tempPoc[list, tempCount[list]]  = poc
                    tempLong[list, tempCount[list]] = false
                    tempCount[list]                 += 1
                }

                for poc in longTerm
                {
                    if tempCount[list] >= needed do
                        break
                    temp[list, tempCount[list]]     = .findByPocLsb(cast(u32) poc & lsbMask, lsbMask)
                    tempPoc[list, tempCount[list]]  = poc
                    tempLong[list, tempCount[list]] = true
                    tempCount[list]                 += 1
                }
            }

            for index in header.numRefIdx[list]
            {
                let source = header.listModification[list] ? header.listEntry[list, index] : index
                if source >= tempCount[list] do
                    fail InvalidFormatError{"HEVC reference list modification is out of range"}

                // A reference the stream names but the buffer never received is replaced by the
                // nearest picture available, which keeps a stream that starts mid-sequence
                // decodable instead of failing on its first predicted picture.
                var frame = temp[list, source]
                if !frame do
                    frame = .nearestReference(tempPoc[list, source])
                if !frame do
                    fail InvalidFormatError{"HEVC slice refers to a picture that was never decoded"}

                .refList.frames[list, index]   = frame
                .refList.poc[list, index]      = tempPoc[list, source]
                .refList.longTerm[list, index] = tempLong[list, source]
            }

            .refList.count[list] = header.numRefIdx[list]
        }
    }

    // Returns the decoded picture closest in order count to `poc`, for a missing reference.
    private mtd nearestReference(poc: s32)->#null *Frame
    {
        var best: #null *Frame
        var bestDistance = Swag.S32.Max
        for index in .referenceCount
        {
            let frame = .references[index].frame!
            if frame == .current do
                continue
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
