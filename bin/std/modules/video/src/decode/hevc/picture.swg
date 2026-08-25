//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns access units, picture lifetime, slice segment data, and entropy synchronization.
//
#global namespace Hevc
#global internal

using Core, Core.Errors

// One independently entropy-coded wavefront row.
//
// The row borrows all picture-wide storage from `owner`, while `worker` owns the arithmetic,
// prediction, coefficient, and transform scratch that makes reconstruction independent. HEVC
// lets a row advance once the row above is two coding tree blocks ahead.
private struct WppRowJob
{
    using base: Jobs.Job
    owner:       #null *Decoder
    worker:      #null *Decoder
    bounds:      #null const [*] u64
    jobs:        #null [*] WppRowJob
    progress:    #null [*] u32
    states:      #null [*] CabacState
    events:      #null [*] Sync.Event
    failed:      #null *u32
    row:         u32
    rowCount:    u32
    width:       u32
    nextScheduled: bool
    errorText:   String
}

impl Decoder
{
    // Reads one network abstraction layer unit, clause 7.3.1.
    //
    // A unit that carries coded picture data starts a picture when it says so, and continues the
    // one already open otherwise. `payload` still carries the two-byte unit header.
    mtd readNalUnit(payload: const [..] u8)->bool fail
    {
        return try .readNalUnitMode(payload, false)
    }

    // Reads one unit while leaving a coded picture's entropy data for a frame owner.
    mtd prepareNalUnit(payload: const [..] u8)->bool fail
    {
        return try .readNalUnitMode(payload, true)
    }

    private mtd readNalUnitMode(payload: const [..] u8, deferPicture: bool)->bool fail
    {
        if @countof(payload) < 3 do
            fail InvalidFormatError{"HEVC network abstraction layer unit is truncated"}
        if (payload[0] & 0x80) != 0 do
            fail InvalidFormatError{"HEVC network abstraction layer unit sets the forbidden bit"}

        let nalType    = cast(u32) (payload[0] >> 1) & 0x3F
        let temporalId = cast(u32) (payload[1] & 7) - 1
        let body       = payload[2 until @countof(payload)]

        switch nalType
        {
        case NalVps:
            return false

        case NalSps, NalPps:
            try .readParameterSet(nalType, body)
            return false

        case NalAud, NalEos, NalEob, NalFillerData, NalPrefixSei, NalSuffixSei:
            return false
        }

        if !isVideoCodingNal(nalType) do
            return false
        return try .decodeSliceSegment(body, nalType, temporalId, deferPicture)
    }

    // Decodes one slice segment, clauses 7.3.6.1 and 7.3.8.1.
    //
    // Returns whether the unit started a new picture, which is what tells the caller a picture
    // finished before it.
    private mtd decodeSliceSegment(body: const [..] u8, nalType, temporalId: u32, deferPicture: bool)->bool fail
    {
        unescapeRbsp(&.rbsp, body)
        var reader: BitReader
        reader.init(.rbsp.toSlice())

        // The picture parameter set is needed to read the rest of the header, and its identifier
        // is the second field, so a first pass reads just enough to resolve it.
        let firstInPicture = reader.bit() != 0
        if isIrapNal(nalType) do
            discard reader.bit()
        let ppsId = reader.ue()
        if ppsId >= 64 or !.pps[ppsId].valid do
            fail InvalidFormatError{"HEVC slice names a picture parameter set that was not received"}

        let pps = &.pps[ppsId]
        let sps = .sequenceOf(pps)
        if !sps do
            fail InvalidFormatError{"HEVC picture parameter set names a sequence that was not received"}

        reader.init(.rbsp.toSlice())
        var header: SliceHeader
        try header.read(&reader, sps!, pps, nalType, &.previousHeader)
        header.nalType    = nalType
        header.temporalId = temporalId

        var started = false
        if firstInPicture
        {
            try .startPicture(sps!, pps, &header, nalType)
            started = true
        }
        elif !.current
        {
            // A picture whose first segment was lost cannot be reconstructed.
            fail InvalidFormatError{"HEVC slice segment continues a picture that was never started"}
        }

        if !header.dependent
        {
            .previousHeader = header
            .sliceAddrRs    = header.segmentAddress
            .sliceIndex     = cast(u32) .sliceParams.count
            .sliceParams.add({header.deblockingDisabled, header.loopFilterAcrossSlices, cast(s8) header.betaOffsetDiv2, cast(s8) header.tcOffsetDiv2})
        }

        .header              = header
        .header.sliceAddress = .sliceAddrRs
        .header.initType     = .initTypeOf(&header)

        if !header.dependent do
            try .applyReferencePictureSet(&header, sps!)

        if deferPicture
        {
            .preparedBody.clear()
            .preparedBody.add(body)
            .preparedHeaderBit = reader.bitPos
            .preparedPicture   = true
            return started
        }

        try .awaitReferencePictures()
        try .decodeSliceData(&reader, body, sps!, pps)
        return started
    }

    // Completes the picture header published by [[prepareNalUnit]].
    mtd decodePreparedPicture()->#null *Frame fail
    {
        if !.preparedPicture do
            return null

        var reader: BitReader
        reader.bitPos    = .preparedHeaderBit
        .preparedPicture = false
        try .awaitReferencePictures()
        try .decodeSliceData(&reader, .preparedBody.toSlice(), .activeSps!, .activePps!)
        return try .finishPicture()
    }

    // Publishes failure so pictures already prepared from this one never wait forever.
    mtd failPreparedPicture()
    {
        .preparedPicture = false
        if .current
        {
            .current!.publishProgress(FrameProgressFailed)
            .current = null
        }
    }

    // Waits until every picture this slice predicts from is complete.
    //
    // A single-lane decoder observes completed references immediately. Frame-threaded streams
    // can publish prediction state before reconstruction, so their later lanes wait here instead
    // of reading a reference plane while its owner is still writing it.
    private mtd awaitReferencePictures() fail
    {
        for list in ListCount
        {
            for index in .refList.count[list]
            {
                let frame = .refList.frames[list, index]
                if !frame do
                    continue
                if frame!.waitProgress(frame!.progressComplete()) == FrameProgressFailed do
                    fail InvalidFormatError{"HEVC inter block has no decoded reference picture"}
            }
        }
    }

    // Returns the context initialization type of one slice, equation 9-7.
    private mtd const initTypeOf(header: const *SliceHeader)->u32
    {
        if header.sliceType == SliceTypeI do
            return 0
        if header.sliceType == SliceTypeP do
            return header.cabacInitFlag ? 2 : 1
        return header.cabacInitFlag ? 1 : 2
    }

    // Opens a new picture and prepares every per-picture table, clause 8.1.3.
    private mtd startPicture(sps: const *Sps, pps: const *Pps, header: const *SliceHeader, nalType: u32) fail
    {
        // A caller feeding units one at a time takes the picture that just closed from here; one
        // feeding whole access units closed it already.
        .finishedFrame = try .finishPicture()
        try .activate(sps, pps)

        // A random access point after a break in the stream drops the pictures that would have
        // predicted from what came before it, clause 8.1.3.
        .noRaslOutput = isIdrNal(nalType) or nalType == NalCraNut or .firstPicture
        .computePoc(nalType, header, sps)
        if isReferenceNal(nalType) and header.temporalId == 0
        {
            .prevPocLsb = header.pocLsb
            .prevPocMsb = .pocMsb
        }

        let frame = .acquireFrame()
        if !frame do
            fail InvalidFormatError{"HEVC decoded picture buffer has no free picture"}

        frame!.prepare(sps)
        frame!.poc          = .pocValue
        frame!.marking      = .ShortTerm
        frame!.outputNeeded = header.picOutputFlag
        frame!.isIrap       = isIrapNal(nalType)
        frame!.noRaslOutput = .noRaslOutput
        try .holdReference(frame!, .ShortTerm)
        .current = frame

        .sliceParams.clear()
        .sliceIndex   = 0
        .sliceAddrRs  = 0
        .saoUsed      = false
        .firstPicture = false

        let blocks = cast(u64) .gridWidth * cast(u64) .gridHeight
        Memory.set(.predMode.buffer!, ModeInter, blocks)
        Memory.set(.intraModeY.buffer!, IntraDc, blocks)
        Memory.set(.ctDepth.buffer!, 0, blocks)
        Memory.set(.skipFlag.buffer!, 0, blocks)
        Memory.set(.cbfLuma.buffer!, 0, blocks)
        Memory.set(.edgeFlags.buffer!, 0, blocks)
        Memory.set(.qpY.buffer!, 0, blocks)
        for index in blocks do
            .motion[index] = PuMotion{}

        if sps.saoEnabled
        {
            .sao.resize(cast(u64) sps.sizeInCtbs)
            for index in cast(u64) sps.sizeInCtbs do
                .sao[index] = SaoParameters{}
        }

        .ctbSliceIndex.resize(cast(u64) sps.sizeInCtbs)
        Memory.set(.ctbSliceAddr.buffer!, 0, cast(u64) sps.sizeInCtbs * #sizeof(u32))
        Memory.set(.ctbSliceIndex.buffer!, 0, cast(u64) sps.sizeInCtbs * #sizeof(u16))
    }

    // Finishes the open picture: loop filters, edge extension, and publication.
    //
    // Returns the picture that finished, or nothing when none was open.
    mtd finishPicture()->#null *Frame fail
    {
        let frame = .current
        if !frame do
            return null

        .deblockPicture()
        .applySampleAdaptiveOffset()
        .storeCollocatedMotion()

        frame!.extendRows(0, frame!.height)
        frame!.extendBorders()
        frame!.publishProgress(frame!.progressComplete())
        .current = null
        return frame
    }

    // Copies the motion of the finished picture into the grid later pictures read, clause 8.5.3.2.8.
    private mtd storeCollocatedMotion()
    {
        let frame = .current!
        let step  = 1'u32 << (ColMotionLog2 - MinBlockLog2)

        for row in frame.colHeight
        {
            for column in frame.colWidth
            {
                let source = &.motion[cast(u64) (row * step) * cast(u64) .gridWidth + cast(u64) (column * step)]

                var record: ColMotion
                record.predFlags = source.predFlags
                for list in ListCount
                {
                    if (cast(u32) source.predFlags & (1'u32 << list)) == 0 do
                        continue
                    record.mv[list, 0] = source.mv[list, 0]
                    record.mv[list, 1] = source.mv[list, 1]

                    let index = cast(u32) source.refIdx[list]
                    if index < .refList.count[list]
                    {
                        record.refPoc[list] = .refList.poc[list, index]
                        if .refList.longTerm[list, index] do
                            record.longTermRef |= cast(u8) (1'u32 << list)
                    }
                }

                frame.colMotion[cast(u64) row * cast(u64) frame.colWidth + cast(u64) column] = record
            }
        }
    }

    // Decodes the coding tree units of one slice segment, clause 7.3.8.1.
    private mtd decodeSliceData(reader: *BitReader, body: const [..] u8, sps: const *Sps, pps: const *Pps) fail
    {
        // The slice data starts on the byte boundary the header ended at.
        let headerBytes  = reader.bitPos >> 3
        let escapedStart = escapedOffsetOf(body, headerBytes)
        if escapedStart >= @countof(body) do
            fail InvalidFormatError{"HEVC slice segment carries no data"}

        let data = body[escapedStart until @countof(body)]

        // Every entry point splits the data into a substream of its own.
        var escapedBounds: Array'u64
        escapedBounds.add(0)
        var running = 0'u64
        for offset in .header.entryPointOffsets
        {
            running += cast(u64) offset
            if running >= @countof(data) do
                fail InvalidFormatError{"HEVC slice entry point runs past the end of its segment"}
            escapedBounds.add(running)
        }

        var bounds: Array'u64
        unescapeRbspWithBounds(&.rbsp, data, escapedBounds.toSlice(), &bounds)
        bounds.add(.rbsp.count)

        // A complete untiled WPP picture has one independently coded substream per coding tree
        // block row. Decode those rows concurrently; less regular slice layouts keep the exact
        // sequential path below.
        if pps.entropyCodingSync and !pps.tilesEnabled and !.header.dependent and !.header.segmentAddress and sps.widthInCtbs >= 2 and bounds.count == cast(u64) sps.heightInCtbs + 1 and Jobs.workerCount() > 1
        {
            try .decodeWavefrontRows(&bounds, sps)
            return
        }

        var substream = 0'u64
        .ctbAddrTs = .ctbRsToTs[.header.segmentAddress]
        .ctbAddrRs = .header.segmentAddress

        // The quantization parameter predictor restarts at the first group of a slice, of a tile,
        // and of a coding tree block row under wavefront processing, clause 8.6.1. A dependent
        // segment continues the slice it belongs to, so only the other two apply to it.
        let startsRow  = pps.entropyCodingSync and (.ctbAddrRs % sps.widthInCtbs) == 0
        let startsTile = pps.tilesEnabled and (.ctbAddrTs == 0 or .tileId[.ctbAddrTs] != .tileId[.ctbAddrTs - 1])
        if !.header.dependent or startsRow or startsTile
        {
            .currentQp    = .header.sliceQp
            .qpYPred      = .header.sliceQp
            .qpYPrev      = .header.sliceQp
            .cuQpDeltaVal = 0
        }

        // A segment that starts a coding tree block row resumes the wavefront rather than the
        // slice, so the row decision comes before the dependent-segment one, clause 9.3.1.
        .claimCodingTreeBlock()
        try .startSubstream(&substream, &bounds)
        if pps.entropyCodingSync and (.ctbAddrRs % sps.widthInCtbs) == 0 and .wppState.valid and .aboveRightAvailable(.ctbAddrRs, sps) do
            .cabac.restore(&.wppState)
        elif .header.dependent and .dependentState.valid do
            .cabac.restore(&.dependentState)
        else do
            .cabac.initContexts(.header.initType, .header.sliceQp)

        for
        {
            if .ctbAddrTs >= sps.sizeInCtbs do
                fail InvalidFormatError{"HEVC slice segment runs past the end of its picture"}

            try .codingTreeUnit()

            // Wavefront processing resumes the next row from the adaptation this one reached at
            // its second block, clause 9.3.2.4.
            if pps.entropyCodingSync and (.ctbAddrRs % sps.widthInCtbs) == 1 do
                .cabac.save(&.wppState)

            let endOfSlice = .cabac.terminate() != 0
            if .cabac.hasOverrun() do
                fail InvalidFormatError{"HEVC slice segment data is truncated"}

            .ctbAddrTs += 1
            if .ctbAddrTs < sps.sizeInCtbs do
                .claimCodingTreeBlock()
            if endOfSlice
            {
                .cabac.save(&.dependentState)
                break
            }

            if .ctbAddrTs >= sps.sizeInCtbs do
                fail InvalidFormatError{"HEVC slice segment does not end inside its picture"}

            let nextRs  = .ctbTsToRs[.ctbAddrTs]
            let newTile = pps.tilesEnabled and .tileId[.ctbAddrTs] != .tileId[.ctbAddrTs - 1]
            let newRow  = pps.entropyCodingSync and (nextRs % sps.widthInCtbs) == 0
            if !newTile and !newRow do
                continue

            // A new substream restarts the arithmetic engine on its own bytes.
            .claimCodingTreeBlock()
            try .startSubstream(&substream, &bounds)
            if newTile
            {
                .cabac.initContexts(.header.initType, .header.sliceQp)
            }
            elif .wppState.valid and .aboveRightAvailable(nextRs, sps)
            {
                .cabac.restore(&.wppState)
            }
            else
            {
                .cabac.initContexts(.header.initType, .header.sliceQp)
            }

            .qpYPrev      = .header.sliceQp
            .cuQpDeltaVal = 0
        }
    }

    // Records which slice the coding tree block about to be decoded belongs to.
    //
    // Availability is answered from this, and the wavefront decision asks about the block above
    // and to the right before the block itself is decoded, so it is claimed first.
    private mtd claimCodingTreeBlock()
    {
        .ctbAddrRs                 = .ctbTsToRs[.ctbAddrTs]
        .ctbSliceAddr[.ctbAddrRs]  = .sliceAddrRs
        .ctbSliceIndex[.ctbAddrRs] = cast(u16) .sliceIndex
    }

    // Reports whether the block above and to the right of a coding tree block was decoded, which
    // is what decides whether a wavefront row resumes or restarts.
    private mtd const aboveRightAvailable(ctbAddrRs: u32, sps: const *Sps)->bool
    {
        let ctbX = ctbAddrRs % sps.widthInCtbs
        let ctbY = ctbAddrRs / sps.widthInCtbs
        if !ctbY or ctbX + 1 >= sps.widthInCtbs do
            return false

        let x = cast(s32) ((ctbX + 1) << sps.ctbLog2Size)
        let y = cast(s32) ((ctbY - 1) << sps.ctbLog2Size)
        return .isAvailable(cast(s32) (ctbX << sps.ctbLog2Size), cast(s32) (ctbY << sps.ctbLog2Size), x, y)
    }

    // Points the arithmetic decoder at the next substream of the slice segment.
    //
    // A segment states one entry point per substream it contains, so running out of them means
    // the segment and its entry points disagree about where its rows begin.
    private mtd startSubstream(substream: *u64, bounds: *Array'u64) fail
    {
        let index = substream[]
        substream[] = index + 1
        if index + 1 >= bounds.count do
            fail InvalidFormatError{"HEVC slice segment has fewer entry points than substreams"}

        let first = bounds[index]
        let last  = bounds[index + 1]
        if last <= first do
            fail InvalidFormatError{"HEVC slice segment substream is empty"}
        .cabac.start(.rbsp.buffer! + first, last - first)
    }

    // Decodes a full-picture wavefront slice using one private scratch decoder per row.
    private mtd decodeWavefrontRows(bounds: *Array'u64, sps: const *Sps) fail
    {
        let rowCount = sps.heightInCtbs
        let width    = sps.widthInCtbs

        var jobs:     Array'WppRowJob
        var progress: Array'u32
        var states:   Array'CabacState
        jobs.resize(rowCount)
        progress.resize(rowCount)
        states.resize(rowCount)

        let workersSize = cast(u64) rowCount * #sizeof(Decoder)
        let workers     = cast([*] Decoder) Memory.alloc(workersSize)
        @init(workers, rowCount)
        let eventsSize = cast(u64) rowCount * #sizeof(Sync.Event)
        let events     = cast([*] Sync.Event) Memory.alloc(eventsSize)
        @init(events, rowCount)
        for row in rowCount do
            events[row].init(manual: true)
        defer
        {
            for row in rowCount do
                events[row].release()
            @drop(events, rowCount)
            Memory.free(events, eventsSize)
            for row in rowCount do
                .detachWavefrontWorker(&workers[row])
            @drop(workers, rowCount)
            Memory.free(workers, workersSize)
        }

        for row in rowCount do
            .prepareWavefrontWorker(&workers[row])

        var failed = 0'u32
        for row in rowCount
        {
            let job = &jobs[row]
            job.owner     = me
            job.worker    = &workers[row]
            job.bounds    = bounds.buffer
            job.jobs      = jobs.buffer
            job.progress  = progress.buffer
            job.states    = states.buffer
            job.events    = events
            job.failed    = &failed
            job.row       = row
            job.rowCount  = rowCount
            job.width     = width
            job.lambda    = &runWppRow
            job.data      = job
        }
        Jobs.schedule(&jobs[0])

        for index in rowCount do
            Jobs.wait(&jobs[index])

        for index in rowCount
        {
            if jobs[index].errorText.length do
                fail InvalidFormatError{Errors.mkString(jobs[index].errorText.toString())}
            .saoUsed = .saoUsed or workers[index].saoUsed
        }

        workers[rowCount - 1].cabac.save(&.dependentState)
        .ctbAddrTs = sps.sizeInCtbs
        .ctbAddrRs = sps.sizeInCtbs - 1
    }

    // Gives a row decoder borrowed views of the picture-wide arrays. Its own fixed scratch and
    // arithmetic reader stay private, so concurrently reconstructed rows never share temporaries.
    private mtd prepareWavefrontWorker(worker: *Decoder)
    {
        worker.activeSps   = .activeSps
        worker.activePps   = .activePps
        worker.current     = .current
        worker.header      = .header
        worker.refList     = .refList
        worker.gridWidth   = .gridWidth
        worker.gridHeight  = .gridHeight
        worker.sliceAddrRs = .sliceAddrRs
        worker.sliceIndex  = .sliceIndex

        worker.zScan.buffer = .zScan.buffer
        worker.zScan.count  = .zScan.count
        worker.ctbRsToTs.buffer = .ctbRsToTs.buffer
        worker.ctbRsToTs.count  = .ctbRsToTs.count
        worker.ctbTsToRs.buffer = .ctbTsToRs.buffer
        worker.ctbTsToRs.count  = .ctbTsToRs.count
        worker.tileId.buffer = .tileId.buffer
        worker.tileId.count  = .tileId.count
        worker.ctbSliceAddr.buffer = .ctbSliceAddr.buffer
        worker.ctbSliceAddr.count  = .ctbSliceAddr.count
        worker.ctbSliceIndex.buffer = .ctbSliceIndex.buffer
        worker.ctbSliceIndex.count  = .ctbSliceIndex.count
        worker.sliceParams.buffer = .sliceParams.buffer
        worker.sliceParams.count  = .sliceParams.count
        worker.predMode.buffer = .predMode.buffer
        worker.predMode.count  = .predMode.count
        worker.intraModeY.buffer = .intraModeY.buffer
        worker.intraModeY.count  = .intraModeY.count
        worker.ctDepth.buffer = .ctDepth.buffer
        worker.ctDepth.count  = .ctDepth.count
        worker.skipFlag.buffer = .skipFlag.buffer
        worker.skipFlag.count  = .skipFlag.count
        worker.qpY.buffer = .qpY.buffer
        worker.qpY.count  = .qpY.count
        worker.cbfLuma.buffer = .cbfLuma.buffer
        worker.cbfLuma.count  = .cbfLuma.count
        worker.motion.buffer = .motion.buffer
        worker.motion.count  = .motion.count
        worker.edgeFlags.buffer = .edgeFlags.buffer
        worker.edgeFlags.count  = .edgeFlags.count
        worker.sao.buffer = .sao.buffer
        worker.sao.count  = .sao.count

        for index in 32'u32 * 32 do
            worker.transformMatrix[index] = .transformMatrix[index]
        worker.transformMatrixReady = true
    }

    // Removes borrowed array headers before normal Decoder destruction sees the worker.
    private mtd detachWavefrontWorker(worker: *Decoder)
    {
        worker.zScan.buffer = null
        worker.ctbRsToTs.buffer = null
        worker.ctbTsToRs.buffer = null
        worker.tileId.buffer = null
        worker.ctbSliceAddr.buffer = null
        worker.ctbSliceIndex.buffer = null
        worker.sliceParams.buffer = null
        worker.predMode.buffer = null
        worker.intraModeY.buffer = null
        worker.ctDepth.buffer = null
        worker.skipFlag.buffer = null
        worker.qpY.buffer = null
        worker.cbfLuma.buffer = null
        worker.motion.buffer = null
        worker.edgeFlags.buffer = null
        worker.sao.buffer = null
        worker.current = null
        worker.activeSps = null
        worker.activePps = null
    }

    // Reconstructs one row while maintaining the two-CTU WPP lead over the row below.
    private mtd decodeWavefrontRow(job: *WppRowJob) fail
    {
        let row = job.row
        .currentQp       = .header.sliceQp
        .qpYPred         = .header.sliceQp
        .qpYPrev         = .header.sliceQp
        .cuQpDeltaVal    = 0
        .isCuQpDeltaCoded = false
        let first = job.bounds![row]
        let last  = job.bounds![row + 1]
        .cabac.start(job.owner!.rbsp.buffer! + first, last - first)

        if row
        {
            if !.waitWavefrontProgress(job, row - 1, 2) do
                return
            .cabac.restore(job.states! + row - 1)
        }
        else do
            .cabac.initContexts(.header.initType, .header.sliceQp)

        for column in job.width
        {
            if row
            {
                let needed = Math.min(column + 2, job.width)
                if !.waitWavefrontProgress(job, row - 1, needed) do
                    return
            }

            .ctbAddrRs = row * job.width + column
            .ctbAddrTs = .ctbAddrRs
            .claimCodingTreeBlock()
            try .codingTreeUnit()

            if column == 1
            {
                .cabac.save(job.states! + row)
                scheduleNextWppRow(job)
            }

            let endOfSlice = .cabac.terminate() != 0
            if .cabac.hasOverrun() do
                fail InvalidFormatError{"HEVC slice segment data is truncated"}

            Atomic.exchange(job.progress! + row, column + 1)
            job.events![row].signal()
            let finalBlock = row + 1 == job.rowCount and column + 1 == job.width
            if endOfSlice != finalBlock do
                fail InvalidFormatError{"HEVC wavefront slice ends outside its final coding tree block"}
        }
    }

    // Sleeps until the row above has made enough progress. Resetting before the second check
    // closes the signal race without burning a worker core while another row reconstructs.
    private mtd waitWavefrontProgress(job: *WppRowJob, row, needed: u32)->bool
    {
        while Atomic.get(job.progress! + row) < needed and Atomic.get(job.failed!) == 0
        {
            job.events![row].reset()
            if Atomic.get(job.progress! + row) < needed and Atomic.get(job.failed!) == 0 do
                job.events![row].wait()
        }

        return Atomic.get(job.failed!) == 0
    }
}

private func runWppRow(data: #null *void)
{
    let job = cast(*WppRowJob) data!
    if Atomic.get(job.failed!) != 0
    {
        scheduleNextWppRow(job)
        return
    }

    catch job.worker!.decodeWavefrontRow(job) as rowError
    if rowError != null
    {
        job.errorText = Errors.message(rowError)
        Atomic.exchange(job.failed!, 1)
        for index in job.rowCount do
            job.events![index].signal()
    }

    scheduleNextWppRow(job)
}

// A WPP row becomes runnable when its predecessor has decoded its second coding tree block.
// Submission at that exact point keeps every scheduler job useful instead of queueing waiters.
private func scheduleNextWppRow(job: *WppRowJob)
{
    if job.nextScheduled do
        return
    job.nextScheduled = true
    if job.row + 1 < job.rowCount do
        Jobs.schedule(job.jobs! + job.row + 1)
}
