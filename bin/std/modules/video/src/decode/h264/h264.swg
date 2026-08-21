#global namespace H264
#global internal

using Core, Core.Errors

// Macroblock classes stored per decoded macroblock for neighbor prediction and deblocking.
const MbClassIntra4x4   = 0'u8
const MbClassIntra8x8   = 1'u8
const MbClassIntra16x16 = 2'u8
const MbClassIPcm       = 3'u8
const MbClassInter      = 4'u8

// One decoded macroblock's summary, kept for the neighbors and the deblocking filter.
struct MbInfo
{
    class:        u8     // One of the MbClass values.
    cbpLuma:      u8     // One coded bit per 8x8 quadrant.
    cbpChroma:    u8     // 0 none, 1 DC only, 2 DC and AC.
    qp:           u8     // Luma QP used by the macroblock.
    chromaMode:   u8     // Intra chroma prediction mode.
    transform8x8: bool
    skipped:      bool     // P or B skip, for the CABAC skip contexts.
    direct:       bool     // B skip or B_Direct_16x16, for the CABAC type contexts.
    sliceId:      u16      // Which slice decoded the macroblock.

    // Deblocking parameters of the owning slice.
    deblockIdc:  u8
    alphaOffset: s8
    betaOffset:  s8

    // Uniform-motion summary for the deblocking fast path: an inter macroblock with no luma
    // coefficients and one motion over its whole grid has strength zero on every inner edge,
    // and one strength for a whole edge against another uniform macroblock.
    uniform: bool
}

// Reads ITU-T H.264 video: one access unit in, one decoded frame out.
//
// The decoder is fed complete access units in decode order, each holding the NAL units of one
// frame, which is what an ISO-BMFF sample is. It performs no output reordering of its own: the
// container knows each sample's composition time and reorders decoded frames itself, so the
// decoder only keeps the reference frames prediction needs.
//
// Only progressive 8-bit 4:2:0 streams are read. Baseline, Constrained Baseline, Main, and
// High profile features are supported: CAVLC and CABAC entropy coding, I, P, and B slices,
// multiple slices per picture, multiple and long-term reference frames, explicit and implicit
// weighted prediction, spatial and temporal direct modes, 8x8 transforms, and scaling lists.
struct Decoder
{
    spsSet:        Array'Sps
    ppsSet:        Array'Pps
    nalLengthSize: u32
    rbsp:          Array'u8     // Unescape scratch, reused across NAL units.

    sps: #null *Sps     // Active sequence set of the current picture.
    pps: #null *Pps     // Active picture set of the current picture.

    pool:      Array'*Frame     // Every allocated frame, owned by the decoder.
    shortRefs: Array'*Frame     // Short-term references, most recent first.
    longRefs:  Array'*Frame     // Long-term references, ascending index.
    current:   #null *Frame     // Picture being decoded.

    // Per-macroblock state of the current picture.
    mbInfo:  Array'MbInfo
    dcFlags: Array'u8     // Three per macroblock: luma, Cb, and Cr DC coded flags.

    // Per-4x4-block state of the current picture, on the absolute block grid: index
    // `(mbY * 4 + y) * mbWidth * 4 + mbX * 4 + x`, and half that pitch for chroma.
    intraModes:  Array'u8     // Intra 4x4 prediction mode, DC for non-intra blocks.
    nonZeroLuma: Array'u8     // Nonzero AC coefficient count, for entropy contexts.
    nonZeroCb:   Array'u8     // Chroma AC nonzero counts, one per chroma 4x4 block.
    nonZeroCr:   Array'u8
    codedLuma:   Array'u8     // Any coefficient coded in the block, for deblocking.

    // Per-4x4-block motion state of the current picture, one array per reference list.
    mvL0:        Array's16     // Two components per block.
    mvL1:        Array's16
    refIdxL0:    Array's8
    refIdxL1:    Array's8
    refPocL0:    Array's32     // Picture order count of the referenced frame, for deblocking.
    refPocL1:    Array's32
    mvdL0:       Array's16     // Motion vector differences, for the CABAC contexts.
    mvdL1:       Array's16
    directFlags: Array'u8     // Whether the block was coded in a direct mode.

    // Entropy parsing stays serial inside a slice. Parsed macroblocks and their immutable
    // slice contexts remain here until inter reconstruction fans out through Core.Jobs.
    parsedMbs:       Array'Mb
    parsedResiduals: Array'MbResidual
    parsedExtraJobs: Array'MbExtraJobs
    pictureSlices:   Array'Slice

    decodedMbs: u64
    sliceCount: u32

    // Picture order state carried between pictures.
    prevPocMsb:         s32
    prevPocLsb:         s32
    prevFrameNum:       u32
    prevFrameNumOffset: s32

    // Reference marking of the current picture, parsed from its first slice header.
    markingParsed:   bool
    idrLongTerm:     bool
    adaptiveMarking: bool
    mmcoOps:         Array'MmcoOp
    isIdrPicture:    bool
    isRefPicture:    bool
}

// One memory-management control operation of a slice header.
struct MmcoOp
{
    op:   u32
    arg0: u32
    arg1: u32
}

impl Decoder
{
    // Parses an ISO-BMFF `avcC` decoder configuration: NAL length size plus the initial
    // sequence and picture parameter sets.
    mtd configure(record: const [..] u8) fail
    {
        if @countof(record) < 7 do
            fail InvalidFormatError{"H.264 decoder configuration is truncated"}
        if record[0] != 1 do
            fail UnsupportedFormatError{"H.264 decoder configuration has an unknown version"}

        .nalLengthSize = cast(u32) (record[4] & 3) + 1
        var offset   = 5'u64
        let spsCount = cast(u64) (record[offset] & 0x1F)
        offset += 1
        for spsCount do
            offset = .configureSet(record, offset)
        if offset >= @countof(record) do
            fail InvalidFormatError{"H.264 decoder configuration is truncated"}
        let ppsCount = cast(u64) record[offset]
        offset += 1
        for ppsCount do
            offset = .configureSet(record, offset)
    }

    // Reads one length-prefixed parameter set of the configuration record.
    private mtd configureSet(record: const [..] u8, offset: u64)->u64 fail
    {
        if offset + 2 > @countof(record) do
            fail InvalidFormatError{"H.264 decoder configuration is truncated"}
        let size  = (cast(u64) record[offset] << 8) | cast(u64) record[offset + 1]
        let start = offset + 2
        if size < 1 or start + size > @countof(record) do
            fail InvalidFormatError{"H.264 decoder configuration is truncated"}

        .handleNal(record[start until start + size])
        return start + size
    }

    // Releases every frame the decoder owns.
    mtd opDrop()
    {
        for frame in .pool do
            Memory.delete(frame)
    }

    // Returns a frame to the pool once the container no longer displays it.
    mtd releaseFrame(frame: *Frame)
    {
        frame.heldByCaller = false
    }

    // Flushes prediction state before decoding from a container sync sample.
    mtd restart()
    {
        for reference in .shortRefs do
            reference.isShortTerm = false
        for reference in .longRefs do
            reference.isLongTerm = false
        .shortRefs.clear()
        .longRefs.clear()
        .pictureSlices.clear()
        .current            = null
        .prevPocMsb         = 0
        .prevPocLsb         = 0
        .prevFrameNum       = 0
        .prevFrameNumOffset = 0
    }

    // Decodes one access unit and returns its frame, or null when the unit carries no picture.
    //
    // The returned frame stays valid until it is both released with [[releaseFrame]] and no
    // longer referenced by the stream itself.
    mtd decodeAccessUnit(sample: const [..] u8)->#null *Frame fail
    {
        .current       = null
        .markingParsed = false
        .mmcoOps.clear()
        var offset = 0'u64
        while offset < @countof(sample)
        {
            if offset + .nalLengthSize > @countof(sample) do
                fail InvalidFormatError{"H.264 sample ends inside a NAL length prefix"}
            var size = 0'u64
            for .nalLengthSize
            {
                size   = (size << 8) | cast(u64) sample[offset]
                offset += 1
            }

            if size < 1 or size > @countof(sample) - offset do
                fail InvalidFormatError{"H.264 sample ends inside a NAL unit"}
            .handleNal(sample[offset until offset + size])
            offset += size
        }

        if !.current do
            return null
        .finishPicture()
        let result = .current!
        result.heldByCaller = true
        .current            = null
        return result
    }

    // Returns the first stored sequence parameter set, which carries the stream geometry.
    mtd const firstSps()->#null *Sps
    {
        for &stored in .spsSet where stored.valid do
            return stored
        return null
    }

    // Reports whether an access unit can be omitted while seeking past it. POC type 0 updates
    // its carried order state only for reference pictures, so a non-reference picture cannot
    // affect either prediction or the order of a later target. Other POC types keep the
    // conservative path because their frame-number state also advances on non-reference input.
    mtd const canSkipWhileSeeking(sample: const [..] u8)->bool
    {
        let configured = .firstSps()
        if !configured or configured!.pocType != 0 or .nalLengthSize == 0 do
            return false

        var hasPicture = false
        var offset     = 0'u64
        while offset < @countof(sample)
        {
            if offset + .nalLengthSize > @countof(sample) do
                return false
            var size = 0'u64
            for .nalLengthSize
            {
                size   = (size << 8) | cast(u64) sample[offset]
                offset += 1
            }

            if size < 1 or size > @countof(sample) - offset do
                return false
            let header  = sample[offset]
            let nalType = header & 0x1F
            if nalType == 1 or nalType == 5
            {
                hasPicture = true
                if header & 0x60 do
                    return false
            }

            offset += size
        }

        return hasPicture
    }

    // Dispatches one NAL unit.
    private mtd handleNal(nal: const [..] u8) fail
    {
        let header = nal[0]
        if header & 0x80 do
            fail InvalidFormatError{"H.264 NAL unit has a set forbidden bit"}
        let refIdc  = cast(u32) header >> 5
        let nalType = cast(u32) header & 0x1F

        switch nalType
        {
        case 1, 5:
            unescapeRbsp(&.rbsp, nal[1 until @countof(nal)])
            .decodeSliceNal(refIdc, nalType == 5)

        case 7:
            unescapeRbsp(&.rbsp, nal[1 until @countof(nal)])
            .parseSpsNal()

        case 8:
            unescapeRbsp(&.rbsp, nal[1 until @countof(nal)])
            .parsePpsNal()

        case 2, 3, 4:
            fail UnsupportedFormatError{"video decoder does not support H.264 data partitioning"}

        case 20:
            fail UnsupportedFormatError{"video decoder does not support scalable or multiview H.264 streams"}

        default:

            // Access-unit delimiters, SEI messages, filler, and end markers carry nothing the
            // decoder needs.
            break
        }
    }

    // Decodes one coded slice NAL unit.
    private mtd decodeSliceNal(refIdc: u32, isIdr: bool) fail
    {
        var slice: Slice
        if !slice.parseHeader(me, refIdc, isIdr) do
            return

        if !.current
        {
            .isRefPicture = refIdc != 0
            .isIdrPicture = isIdr
            let poc = .computePoc(&slice.header)
            .startPicture(slice.header.frameNum, poc)
        }

        .sliceCount   += 1
        slice.sliceId = cast(u16) .sliceCount
        if slice.header.type != SliceTypeI do
            slice.buildLists()
        .pictureSlices.add(#move slice)
        .pictureSlices[.pictureSlices.count - 1].decodeData()
    }

    // Parses one sequence parameter set and stores it under its identifier.
    private mtd parseSpsNal() fail
    {
        // The identifier sits after the fixed 24-bit profile and level header.
        var probe: BitReader
        probe.init(.rbsp.toSlice())
        probe.skip(24)
        let id = probe.ue()
        if probe.overran or id > 31 do
            fail InvalidFormatError{"H.264 sequence parameter set is truncated"}

        var parsed: Sps
        parsed.parse(.rbsp.toSlice())
        if .spsSet.count <= id do
            .spsSet.resize(id + 1)
        .spsSet[id] = #move parsed
    }

    // Parses one picture parameter set and stores it under its identifier.
    private mtd parsePpsNal() fail
    {
        var probe: BitReader
        probe.init(.rbsp.toSlice())
        let id = probe.ue()
        if probe.overran or id > 255 do
            fail InvalidFormatError{"H.264 picture parameter set is truncated"}
        let spsId = probe.ue()
        if spsId > 31 or spsId >= .spsSet.count or !.spsSet[spsId].valid do
            fail InvalidFormatError{"H.264 picture set references an unknown sequence set"}

        var parsed: Pps
        parsed.parse(.rbsp.toSlice(), &.spsSet[spsId])
        if .ppsSet.count <= id do
            .ppsSet.resize(id + 1)
        .ppsSet[id] = #move parsed
    }

    // Allocates or reuses a frame for the picture that starts decoding.
    mtd startPicture(frameNum: u32, poc: s32) fail
    {
        var found: #null *Frame
        for candidate in .pool where !candidate.heldByCaller and !candidate.isReference()
        {
            found = candidate
            break
        }

        if !found
        {
            if .pool.count >= 34 do
                fail InvalidFormatError{"H.264 stream holds more frames alive than a valid stream can"}
            let created = Memory.new'Frame()
            .pool.add(created)
            found = created
        }

        let sps   = .sps!
        let frame = found!
        frame.prepare(sps.mbWidth, sps.mbHeight)
        frame.frameNum = frameNum
        frame.poc      = poc
        .current       = frame

        let mbCount = cast(u64) sps.mbWidth * cast(u64) sps.mbHeight
        let blocks  = mbCount * 16
        if .mbInfo.count != mbCount
        {
            .mbInfo.resize(mbCount)
            .dcFlags.resize(mbCount * 3)
            .intraModes.resize(blocks)
            .nonZeroLuma.resize(blocks)
            .nonZeroCb.resize(mbCount * 4)
            .nonZeroCr.resize(mbCount * 4)
            .codedLuma.resize(blocks)
            .mvL0.resize(blocks * 2)
            .mvL1.resize(blocks * 2)
            .refIdxL0.resize(blocks)
            .refIdxL1.resize(blocks)
            .refPocL0.resize(blocks)
            .refPocL1.resize(blocks)
            .mvdL0.resize(blocks * 2)
            .mvdL1.resize(blocks * 2)
            .directFlags.resize(blocks)
            .parsedMbs.resize(mbCount)
            .parsedResiduals.resize(mbCount)
            .parsedExtraJobs.resize(mbCount)
        }

        // A stale slice id would make a mb from the previous picture look like a neighbor.
        for &info in .mbInfo do
            info.sliceId = 0

        .decodedMbs = 0
        .sliceCount = 0
        .pictureSlices.clear()
    }

    // Completes the current picture: filters it, publishes its edges, and applies its
    // reference marking.
    private mtd finishPicture() fail
    {
        let sps     = .sps!
        let mbCount = cast(u64) sps.mbWidth * cast(u64) sps.mbHeight
        if .decodedMbs != mbCount do
            fail InvalidFormatError{"H.264 access unit does not cover the whole picture"}

        .reconstructPicture()
        deblockPicture(me)
        let frame = .current!
        frame.extendEdges()
        .applyMarking(frame)
    }

    // Applies the reference-picture marking of the finished picture, section 8.2.5.
    private mtd applyMarking(frame: *Frame) fail
    {
        if .isIdrPicture
        {
            for reference in .shortRefs do
                reference.isShortTerm = false
            for reference in .longRefs do
                reference.isLongTerm = false
            .shortRefs.clear()
            .longRefs.clear()

            if !.isRefPicture do
                return
            if .idrLongTerm
            {
                frame.isLongTerm  = true
                frame.longTermIdx = 0
                .longRefs.add(frame)
            }
            else
            {
                frame.isShortTerm = true
                .shortRefs.insertAt(0, frame)
            }

            return
        }

        if !.isRefPicture do
            return

        if .adaptiveMarking do
            .applyMmco(frame)

        if !frame.isLongTerm
        {
            // Sliding window: the oldest short-term reference leaves when the buffer is full.
            let maxRefs = Math.max(.sps!.maxRefFrames, 1)
            while .shortRefs.count + .longRefs.count >= cast(u64) maxRefs and .shortRefs.count
            {
                let oldest = .shortRefs.back()
                oldest.isShortTerm = false
                discard .shortRefs.popBack()
            }

            frame.isShortTerm = true
            .shortRefs.insertAt(0, frame)
        }
    }

    // Executes the memory-management control operations of the current picture.
    private mtd applyMmco(frame: *Frame) fail
    {
        let maxFrameNum = 1's32 << .sps!.log2MaxFrameNum
        for operation in .mmcoOps
        {
            switch operation.op
            {
            case 1:
                let wanted = cast(s32) frame.frameNum - cast(s32) (operation.arg0 + 1)
                for index in .shortRefs.count where .mmcoPicNum(.shortRefs[index], frame, maxFrameNum) == wanted
                {
                    .shortRefs[index].isShortTerm = false
                    .shortRefs.removeAtOrdered(index)
                    break
                }

            case 2:
                for index in .longRefs.count where .longRefs[index].longTermIdx == cast(s32) operation.arg0
                {
                    .longRefs[index].isLongTerm = false
                    .longRefs.removeAtOrdered(index)
                    break
                }

            case 3:
                let wanted = cast(s32) frame.frameNum - cast(s32) (operation.arg0 + 1)
                for index in .shortRefs.count where .mmcoPicNum(.shortRefs[index], frame, maxFrameNum) == wanted
                {
                    let moved = .shortRefs[index]
                    .shortRefs.removeAtOrdered(index)
                    moved.isShortTerm = false
                    .unmarkLongIndex(cast(s32) operation.arg1)
                    moved.isLongTerm  = true
                    moved.longTermIdx = cast(s32) operation.arg1
                    .insertLong(moved)
                    break
                }

            case 4:
                let maxIdx = cast(s32) operation.arg0 - 1
                var index  = 0'u64
                while index < .longRefs.count
                {
                    if .longRefs[index].longTermIdx > maxIdx
                    {
                        .longRefs[index].isLongTerm = false
                        .longRefs.removeAtOrdered(index)
                        continue
                    }

                    index += 1
                }

            case 5:
                for reference in .shortRefs do
                    reference.isShortTerm = false
                for reference in .longRefs do
                    reference.isLongTerm = false
                .shortRefs.clear()
                .longRefs.clear()
                .prevPocMsb         = 0
                .prevPocLsb         = frame.poc
                .prevFrameNum       = 0
                .prevFrameNumOffset = 0
                frame.frameNum      = 0
                frame.poc           = 0

            case 6:
                .unmarkLongIndex(cast(s32) operation.arg0)
                frame.isLongTerm  = true
                frame.longTermIdx = cast(s32) operation.arg0
                .insertLong(frame)

            default:
                fail InvalidFormatError{"H.264 slice carries an unknown reference marking operation"}
            }
        }
    }

    // Returns the picture number of a short-term reference relative to the current picture.
    private mtd const mmcoPicNum(reference, frame: *Frame, maxFrameNum: s32)->s32
    {
        let wrap = cast(s32) reference.frameNum > cast(s32) frame.frameNum ? cast(s32) reference.frameNum - maxFrameNum : cast(s32) reference.frameNum
        return wrap
    }

    // Removes any long-term reference already using `index`.
    private mtd unmarkLongIndex(index: s32)
    {
        for position in .longRefs.count where .longRefs[position].longTermIdx == index
        {
            .longRefs[position].isLongTerm = false
            .longRefs.removeAtOrdered(position)
            break
        }
    }

    // Inserts a long-term reference keeping the list sorted by index.
    private mtd insertLong(frame: *Frame)
    {
        for position in .longRefs.count where .longRefs[position].longTermIdx > frame.longTermIdx
        {
            .longRefs.insertAt(position, frame)
            return
        }

        .longRefs.add(frame)
    }

    // Computes the picture order count of the picture a slice header starts, section 8.2.1.
    mtd computePoc(header: *SliceHeader)->s32
    {
        let sps         = .sps!
        let maxFrameNum = 1's32 << sps.log2MaxFrameNum
        let frameNum    = cast(s32) header.frameNum

        switch sps.pocType
        {
        case 0:
            let maxLsb = 1's32 << sps.log2MaxPocLsb
            let lsb    = cast(s32) header.pocLsb
            var msb    = .prevPocMsb
            if header.isIdr
            {
                msb         = 0
                .prevPocLsb = 0
            }

            if lsb < .prevPocLsb and .prevPocLsb - lsb >= maxLsb / 2 do
                msb += maxLsb
            elif lsb > .prevPocLsb and lsb - .prevPocLsb > maxLsb / 2 do
                msb -= maxLsb

            let top    = msb + lsb
            let bottom = top + header.deltaPocBottom
            if .isRefPicture
            {
                .prevPocMsb = msb
                .prevPocLsb = lsb
            }

            return Math.min(top, bottom)

        case 1:
            var frameNumOffset = 0's32
            if !header.isIdr
            {
                frameNumOffset = .prevFrameNumOffset
                if cast(s32) .prevFrameNum > frameNum do
                    frameNumOffset += maxFrameNum
            }

            .prevFrameNumOffset = frameNumOffset
            .prevFrameNum       = header.frameNum

            let cycleCount = cast(s32) .sps!.pocCycle.count
            if !cycleCount do
                return 0

            var absFrameNum = frameNumOffset + frameNum
            if !.isRefPicture and absFrameNum > 0 do
                absFrameNum -= 1

            var expectedDelta = 0's32
            for offset in sps.pocCycle do
                expectedDelta += offset

            var expected = 0's32
            if absFrameNum > 0
            {
                let cycles  = (absFrameNum - 1) / cycleCount
                let inCycle = (absFrameNum - 1) % cycleCount
                expected = cycles * expectedDelta
                for index in cast(u64) inCycle + 1 do
                    expected += .sps!.pocCycle[index]
            }

            if !.isRefPicture do
                expected += sps.offsetForNonRefPic

            let top    = expected + header.deltaPoc0
            let bottom = top + sps.offsetForTopToBottom + header.deltaPocBottom
            return Math.min(top, bottom)

        case 2:
            var frameNumOffset = 0's32
            if !header.isIdr
            {
                frameNumOffset = .prevFrameNumOffset
                if cast(s32) .prevFrameNum > frameNum do
                    frameNumOffset += maxFrameNum
            }

            .prevFrameNumOffset = frameNumOffset
            .prevFrameNum       = header.frameNum

            let base = 2 * (frameNumOffset + frameNum)
            return .isRefPicture ? base : base - 1
        }

        return 0
    }
}
