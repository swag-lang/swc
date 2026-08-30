//! Format: H.265/HEVC decoder component.
//! Supported: Progressive Main and Main 10 streams: 8- and 10-bit 4:2:0, I/P/B slices, tiles, wavefront parallel processing, dependent slice segments, sample adaptive offset, and in-loop deblocking.
//! Not supported: 4:2:2 and 4:4:4 chroma, bit depths above 10, pulse code modulation blocks, separate colour planes, and the range, multilayer, 3D, and screen content extensions.
//! Role: This file owns an indexed track: display order, seeking, and decoding on demand.
//
#global namespace Hevc
#global internal

using Core, Core.Errors, Pixel

// How far a stream may reorder before the reader gives up on it.
//
// The format allows sixteen pictures in the buffer, and a picture waiting for display holds one;
// past that the stream is not reordering, it is malformed.
private const MaxReorderDepth       = 17'u64
private const HevcMaxFrameThreads   = 8'u32
private const HevcNoLane            = Swag.U32.Max
private const HevcBytesPerLanePixel = 6'u64
private const HevcLaneMemoryBudget  = 640 * 1024 * 1024'u64

// How many pixels of picture one frame thread is worth; see the H.264 stream for the reasoning.
private const HevcPixelsPerLane   = 480_000'u64
private const HevcMinFrameThreads = 2'u32

// One reconstructed picture waiting for its display turn.
private struct PendingFrame
{
    frame: #null *Frame
    rank:  u64
}

private enum HevcLaneState
{
    Free
    Decoding
}

#[Swag.NoCopy]
private struct HevcFrameThread
{
    thread:    Threading.Thread
    wake:      Sync.Event
    done:      Sync.Event
    decoder:   #null *Decoder
    frame:     #null *Frame
    errorText: String
}

private struct ThreadedHevcSample
{
    lane: u32
    rank: u64
}

private struct DecodedHevcSample
{
    frame: *Frame
    rank:  u64
}

// Drives an indexed H.265 stream independently of its container.
//
// The container hands over the access units of one track in decoding order with the presentation
// time of each; this resolves display order from those times, decodes on demand, and holds the
// pictures a reordered stream produces early.
#[Swag.NoCopy]
struct HevcStream
{
    decoders:     [HevcMaxFrameThreads] Decoder
    frameThreads: [HevcMaxFrameThreads] HevcFrameThread
    payloads:     [HevcMaxFrameThreads] Array'u8
    laneStates:   [HevcMaxFrameThreads] HevcLaneState
    threaded:     [HevcMaxFrameThreads] ThreadedHevcSample
    config:       Array'u8
    lengthSize:   u32 = 4
    frames:       Array'SampleEntry     // Samples in decode order.
    rankOfSample: Array'u32             // Display rank of each decode-order sample.
    sampleAtRank: Array'u32             // Decode-order sample of each display rank.
    syncFlags:    Array'u8
    pending:      Array'PendingFrame

    threadedHead:   u32
    threadedTail:   u32
    threadedCount:  u32
    laneCount:      u32 = 1
    lastSetupLane:  u32 = HevcNoLane
    threadsStarted: bool

    nextDecode:          u64     // Next sample to decode.
    nextRank:            u64     // Display rank the next decode call returns.
    skipBefore:          u64
    prefix:              Array'u8      // Bytes the container took off the front of every stored frame.
    dropped:             Array'u64     // Display ranks of pictures the standard says not to show.
    decodeLimit:         u64 = Swag.U64.Max
    reachedEnd:          bool
    skippedNonReference: u64
    width:               s32
    height:              s32
}

impl HevcStream
{
    // Configures the decoder from a container's decoder configuration and installs the samples.
    mtd open(config: const [..] u8, frames: Array'SampleEntry) fail
    {
        if !config.count do
            fail InvalidFormatError{"H.265 track has no decoder configuration"}

        .config.clear()
        .config.add(config)
        for lane in HevcMaxFrameThreads do
            try .configure(&.decoders[lane])

        .laneCount = Math.max(1'u32, Math.min(Jobs.workerCount(), HevcMaxFrameThreads))
        let pixels = cast(u64) .width * cast(u64) .height
        let wanted = cast(u32) Math.min((pixels + HevcPixelsPerLane - 1) / HevcPixelsPerLane, cast(u64) HevcMaxFrameThreads)
        .laneCount = Math.min(.laneCount, Math.max(wanted, HevcMinFrameThreads))
        let laneBytes = pixels * HevcBytesPerLanePixel
        if laneBytes do
            .laneCount = Math.max(1'u32, Math.min(.laneCount, cast(u32) Math.max(HevcLaneMemoryBudget / laneBytes, 1'u64)))
        if .hasWavefrontConfiguration() do
            .laneCount = Math.min(.laneCount, 4'u32)
        .installFrames(#move frames)
    }

    // Wavefront pictures already spend the global workers across their independently coded rows.
    // Starting several such pictures at once would fill that same queue with dependency waiters.
    private mtd const hasWavefrontConfiguration()->bool
    {
        for index in 64'u32 where .decoders[0].pps[index].valid and .decoders[0].pps[index].entropyCodingSync do
            return true
        return false
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: Array'SampleEntry) fail
    {
        .stopFrameThreads()
        .releasePending()
        .clearFrameThreads()
        for lane in HevcMaxFrameThreads
        {
            .decoders[lane].reset()
            try .configure(&.decoders[lane])
        }

        .nextDecode  = 0
        .nextRank    = 0
        .skipBefore  = 0
        .decodeLimit = Swag.U64.Max
        .dropped.clear()
        .reachedEnd = false
        .installFrames(#move frames)
    }

    // Reads the parameter sets a container carries beside the stream, ISO/IEC 14496-15.
    private mtd configure(decoder: *Decoder) fail
    {
        let config = .config.toSlice()
        if config.count < 23 do
            fail InvalidFormatError{"H.265 decoder configuration is truncated"}
        if config[0] != 1 do
            fail UnsupportedFormatError{"H.265 decoder configuration uses an unknown version"}

        .lengthSize = cast(u32) (config[21] & 3) + 1
        let arrays = cast(u32) config[22]

        var offset = 23'u64
        for arrays
        {
            if offset + 3 > config.count do
                fail InvalidFormatError{"H.265 decoder configuration is truncated"}
            let count = (cast(u32) config[offset + 1] << 8) | cast(u32) config[offset + 2]
            offset += 3

            for count
            {
                if offset + 2 > config.count do
                    fail InvalidFormatError{"H.265 decoder configuration is truncated"}
                let length = (cast(u64) config[offset] << 8) | cast(u64) config[offset + 1]
                offset += 2
                if offset + length > config.count do
                    fail InvalidFormatError{"H.265 decoder configuration is truncated"}
                discard try decoder.readNalUnit(config[offset until offset + length])
                offset += length
            }
        }

        // The geometry the reader reports comes from the sequence the sets describe.
        var sequence: #null const *Sps
        for index in 16'u32 where decoder.sps[index].valid
        {
            sequence = &decoder.sps[index]
            break
        }

        if !sequence do
            fail InvalidFormatError{"H.265 decoder configuration has no sequence parameter set"}
        .width  = cast(s32) sequence!.visibleWidth()
        .height = cast(s32) sequence!.visibleHeight()
    }

    // Builds the display order of the installed samples from their presentation times.
    private mtd installFrames(frames: Array'SampleEntry)
    {
        .frames = #move frames
        let count = .frames.count

        // Real streams are nearly sorted already, off by at most the reorder depth, so inserting
        // each sample into place costs a bounded walk rather than a sort.
        var order: Array'u32
        order.reserve(count)
        for index in count
        {
            var position = order.count
            while position > 0 and .frames[cast(u64) order[position - 1]].presentationTime > .frames[index].presentationTime do
                position -= 1
            order.insertAt(position, cast(u32) index)
        }

        .rankOfSample.clear()
        .sampleAtRank.clear()
        .rankOfSample.resize(count)
        .sampleAtRank.resize(count)
        for rank in order.count
        {
            .sampleAtRank[rank] = order[rank]
            .rankOfSample[cast(u64) order[rank]] = cast(u32) rank
        }

        .syncFlags.clear()
        .syncFlags.resize(count)
        for index in count where .frames[index].isSync do
            .syncFlags[index] = 1
        if count do
            .syncFlags[0] = 1
    }

    // Extends a running stream with samples the container has since indexed.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        if !frames.count do
            return

        var merged: Array'SampleEntry
        merged.reserve(.frames.count + frames.count)
        for entry in .frames do
            merged.add(entry[])
        for entry in frames do
            merged.add(entry[])

        let decode = .nextDecode
        let rank   = .nextRank
        let limit  = .decodeLimit
        let skip   = .skipBefore
        .installFrames(#move merged)
        .nextDecode  = decode
        .nextRank    = rank
        .decodeLimit = limit
        .skipBefore  = skip
    }

    mtd opDrop()
    {
        .stopFrameThreads()
        .releasePending()
        .clearFrameThreads()
        .shutdownFrameThreads()
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    mtd const syncRankAt(rank: u64)->u64
    {
        var scan = rank
        while scan < .frames.count
        {
            if .syncFlags[cast(u64) .sampleAtRank[scan]] != 0 do
                return scan
            scan += 1
        }

        return .frames.count
    }

    // Returns the container presentation timestamp of one display-order picture.
    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        Debug.assert(rank < .sampleAtRank.count)
        return .frames[cast(u64) .sampleAtRank[rank]].presentationTime
    }

    // Positions the stream so the next decoded frame has display rank `rank`.
    mtd seekTo(rank: u64)
    {
        if rank == .nextRank do
            return

        .stopFrameThreads()
        let sample = cast(u64) .sampleAtRank[rank]
        var sync   = sample
        while sync > 0 and .syncFlags[sync] == 0 do
            sync -= 1

        var alreadyPending = false
        for entry in .pending where entry.rank == rank
        {
            alreadyPending = true
            break
        }

        // Advancing within the current decode window keeps every reference picture already
        // reconstructed. Restart only for a backward seek, or when the requested picture needs
        // a clean decode point beyond the samples currently queued.
        if rank < .nextRank or (!alreadyPending and sync > .nextDecode)
        {
            .releasePending()
            .clearFrameThreads()
            for lane in HevcMaxFrameThreads
            {
                .decoders[lane].reset()
                discard catch .configure(&.decoders[lane])
            }

            .nextDecode = sync
            .reachedEnd = false
        }
        else
        {
            .releasePendingBelow(rank)
        }

        .skipBefore  = rank
        .decodeLimit = sample + 1
        .nextRank    = rank
    }

    // Releases every pending picture whose display rank precedes `rank`.
    mtd releasePendingBelow(rank: u64)
    {
        var index = 0'u64
        while index < .pending.count
        {
            if .pending[index].rank < rank
            {
                .release(.pending[index].frame!)
                .pending.removeAtOrdered(index)
                continue
            }

            index += 1
        }
    }

    // Releases every picture waiting for display.
    mtd releasePending()
    {
        for entry in .pending do
            .release(entry.frame!)
        .pending.clear()
    }

    // Reports one picture as shown, so the decoded picture buffer can take its storage back.
    //
    // The container states display order, so the buffer's own output process of clause C.5.2
    // never runs here. A picture therefore stops being needed for output exactly when this stream
    // is done with it, and until it does the buffer counts it as occupied.
    private mtd release(frame: *Frame)
    {
        frame.outputNeeded = false
        Atomic.exchange(&frame.heldByCaller, 0)
    }

    // Decodes the picture with the current display rank and hands over its planes unconverted.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        let frame = try .nextDisplayFrame(source)
        frame.writePlanar(target)
        .release(frame)
    }

    // Decodes the picture with the current display rank and converts it to packed colour.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        var planes: PlanarFrame
        try .decodeNextPlanes(source, &planes)
        planes.view().convertToRgb(target)
    }

    // Decodes until the picture of the current display rank is available.
    private mtd nextDisplayFrame(source: *Source)->*Frame fail
    {
        for
        {
            // A rank whose picture turned out not to be shown moves on to the next one.
            while .takeDropped(.nextRank) do
                .nextRank += 1

            for index in .pending.count where .pending[index].rank == .nextRank
            {
                let frame = .pending[index].frame!
                .pending.removeAtOrdered(index)
                .nextRank    += 1
                .decodeLimit = Swag.U64.Max
                return frame
            }

            if .threadedCount == 0 and .nextDecode >= .decodeLimit and .decodeLimit != Swag.U64.Max do
                .decodeLimit = Swag.U64.Max

            if .threadedCount == 0 and .reachedEnd do
                fail InvalidFormatError{"H.265 stream has no picture for the requested position"}

            let decoded = try .decodeStoredSample(source)
            if !decoded.frame.outputNeeded
            {
                // A picture the standard says not to show still takes a place in the numbering the
                // container states, and that place is answered by the next picture that is shown.
                .dropped.add(decoded.rank)
                .release(decoded.frame)
                continue
            }

            if decoded.rank < .skipBefore
            {
                .release(decoded.frame)
                continue
            }

            .pending.add({decoded.frame, decoded.rank})
            if .pending.count > MaxReorderDepth do
                fail InvalidFormatError{"H.265 stream reorders more pictures than the buffer holds"}
        }
    }

    // Creates the persistent frame owners.
    //
    // They run below normal priority. Frame threading deliberately decodes far ahead of whatever
    // consumes the pictures, so a lane is almost always working on something that is not needed
    // yet; at this resolution there are enough of them to keep a consumer that has to present on
    // a clock off the processor, and a decoder that races ahead while the picture on screen
    // stutters has won nothing.
    private mtd ensureFrameThreads() fail
    {
        if .threadsStarted do
            return

        defer #fail .shutdownFrameThreads()
        for lane in .laneCount
        {
            let frameThread = &.frameThreads[lane]
            frameThread.wake.init(false)
            frameThread.done.init(true)
            frameThread.thread.init(&runHevcFrameThread, frameThread, priority: .BelowNormal)
            frameThread.thread.start()
        }

        .threadsStarted = true
    }

    private mtd shutdownFrameThreads()
    {
        for lane in .laneCount where .frameThreads[lane].thread.isValid() do
            .frameThreads[lane].thread.safeForceEnd()
        for lane in .laneCount where .frameThreads[lane].wake.isValid() do
            .frameThreads[lane].wake.signal()
        for lane in .laneCount where .frameThreads[lane].thread.isValid() do
            .frameThreads[lane].thread.wait()
        for lane in .laneCount
        {
            .frameThreads[lane].wake.release()
            .frameThreads[lane].done.release()
        }

        .threadsStarted = false
    }

    private mtd stopFrameThreads()
    {
        var index = .threadedHead
        for .threadedCount
        {
            .frameThreads[.threaded[index].lane].done.wait()
            index = (index + 1) % HevcMaxFrameThreads
        }
    }

    private mtd clearFrameThreads()
    {
        var index = .threadedHead
        for .threadedCount
        {
            let lane        = .threaded[index].lane
            let frameThread = &.frameThreads[lane]
            if frameThread.frame do
                .release(frameThread.frame!)
            frameThread.frame = null
            .laneStates[lane] = .Free
            index             = (index + 1) % HevcMaxFrameThreads
        }

        .threadedHead  = 0
        .threadedTail  = 0
        .threadedCount = 0
        .lastSetupLane = HevcNoLane
    }

    private mtd reserveLane()->u32
    {
        for lane in .laneCount
        {
            if .laneCount > 1 and lane == .lastSetupLane do
                continue
            if .laneStates[lane] == .Free
            {
                .laneStates[lane] = .Decoding
                return lane
            }
        }

        return HevcNoLane
    }

    private mtd startFrame(source: *Source)->bool fail
    {
        let lane = .reserveLane()
        if lane == HevcNoLane do
            return false

        let decoder = &.decoders[lane]
        if .lastSetupLane != HevcNoLane and lane != .lastSetupLane do
            decoder.inheritPredictionState(&.decoders[.lastSetupLane])

        if .nextDecode >= .frames.count or .nextDecode >= .decodeLimit
        {
            .laneStates[lane] = .Free
            if .nextDecode >= .frames.count do
                .reachedEnd = true
            return false
        }

        let sample  = .nextDecode
        let entry   = .frames[sample]
        let payload = &.payloads[lane]
        try readStoredFrame(source, entry, .prefix.toSlice(), payload)

        .nextDecode += 1
        if .nextDecode >= .frames.count do
            .reachedEnd = true

        let frameThread = &.frameThreads[lane]
        frameThread.decoder   = decoder
        frameThread.frame     = null
        frameThread.errorText = ""
        frameThread.done.reset()

        let codedUnits = try .codedUnitCount(payload.toSlice())
        let rank       = cast(u64) .rankOfSample[sample]
        if rank < .skipBefore and !try .isReferenceAccessUnit(payload.toSlice())
        {
            try .readAuxiliaryUnits(decoder, payload.toSlice())
            .laneStates[lane]    = .Free
            .skippedNonReference += 1
            return true
        }

        if codedUnits == 1
        {
            if !try .prepareAccessUnit(decoder, payload.toSlice()) do
                fail InvalidFormatError{"H.265 access unit carries no picture"}
        }
        else
        {
            let frame = try .decodeAccessUnit(decoder, payload.toSlice())
            if !frame do
                fail InvalidFormatError{"H.265 access unit carries no picture"}
            Atomic.exchange(&frame!.heldByCaller, 1)
            frameThread.frame = frame
            frameThread.done.signal()
        }

        .threaded[.threadedTail] = {lane, rank}
        .threadedTail            = (.threadedTail + 1) % HevcMaxFrameThreads
        .threadedCount           += 1
        .lastSetupLane           = lane
        if codedUnits == 1 do
            frameThread.wake.signal()
        return true
    }

    private mtd fillFrameThreads(source: *Source) fail
    {
        .ensureFrameThreads()
        while .threadedCount < .laneCount and !.reachedEnd
        {
            if !try .startFrame(source) do
                break
        }
    }

    private mtd decodeStoredSample(source: *Source)->DecodedHevcSample fail
    {
        try .fillFrameThreads(source)
        if .threadedCount == 0 do
            fail InvalidFormatError{"H.265 stream ends before the requested picture"}

        let threaded = .threaded[.threadedHead]
        .threadedHead  = (.threadedHead + 1) % HevcMaxFrameThreads
        .threadedCount -= 1

        let frameThread = &.frameThreads[threaded.lane]
        frameThread.done.wait()
        if frameThread.errorText.length do
            fail InvalidFormatError{Errors.mkString(frameThread.errorText.toString())}
        if !frameThread.frame do
            fail InvalidFormatError{"H.265 access unit carries no picture"}

        let frame = frameThread.frame!
        frameThread.frame          = null
        .laneStates[threaded.lane] = .Free
        try .fillFrameThreads(source)
        return {frame, threaded.rank}
    }

    private mtd codedUnitCount(data: const [..] u8)->u32 fail
    {
        var count  = 0'u32
        var offset = 0'u64
        while offset + cast(u64) .lengthSize <= data.count
        {
            let length = try .unitLength(data, &offset)
            if length < 2 do
                fail InvalidFormatError{"H.265 access unit holds a truncated network abstraction layer unit"}
            let nalType = cast(u32) (data[offset] >> 1) & 0x3F
            if isVideoCodingNal(nalType) do
                count += 1
            offset += length
        }

        return count
    }

    // Reports whether an access unit can be referenced by a later picture.
    private mtd isReferenceAccessUnit(data: const [..] u8)->bool fail
    {
        var hasPicture = false
        var offset     = 0'u64
        while offset + cast(u64) .lengthSize <= data.count
        {
            let length = try .unitLength(data, &offset)
            if length < 2 do
                fail InvalidFormatError{"H.265 access unit holds a truncated network abstraction layer unit"}
            let nalType = cast(u32) (data[offset] >> 1) & 0x3F
            if isVideoCodingNal(nalType)
            {
                hasPicture = true
                if isReferenceNal(nalType) do
                    return true
            }

            offset += length
        }

        if !hasPicture do
            fail InvalidFormatError{"H.265 access unit carries no picture"}
        return false
    }

    // Keeps in-band parameter sets from a discarded non-reference picture.
    private mtd readAuxiliaryUnits(decoder: *Decoder, data: const [..] u8) fail
    {
        var offset = 0'u64
        while offset + cast(u64) .lengthSize <= data.count
        {
            let length  = try .unitLength(data, &offset)
            let nalType = cast(u32) (data[offset] >> 1) & 0x3F
            if !isVideoCodingNal(nalType) do
                discard try decoder.readNalUnit(data[offset until offset + length])
            offset += length
        }
    }

    private mtd prepareAccessUnit(decoder: *Decoder, data: const [..] u8)->bool fail
    {
        var picture = false
        var offset  = 0'u64
        while offset + cast(u64) .lengthSize <= data.count
        {
            let length = try .unitLength(data, &offset)
            if try decoder.prepareNalUnit(data[offset until offset + length]) do
                picture = true
            offset += length
        }

        return picture
    }

    // Takes a display rank off the list of pictures never shown, saying whether it was on it.
    private mtd takeDropped(rank: u64)->bool
    {
        for index in .dropped.count where .dropped[index] == rank
        {
            .dropped.removeAt(index)
            return true
        }

        return false
    }

    // Decodes one length-prefixed access unit through the multi-slice fallback.
    private mtd decodeAccessUnit(decoder: *Decoder, data: const [..] u8)->#null *Frame fail
    {
        var offset = 0'u64
        while offset + cast(u64) .lengthSize <= data.count
        {
            let length = try .unitLength(data, &offset)
            discard try decoder.readNalUnit(data[offset until offset + length])
            offset += length
        }

        return try decoder.finishPicture()
    }

    private mtd unitLength(data: const [..] u8, offset: *u64)->u64 fail
    {
        var length = 0'u64
        for index in .lengthSize do
            length = (length << 8) | cast(u64) data[offset[] + cast(u64) index]
        offset[] += cast(u64) .lengthSize
        if !length or offset[] + length > data.count do
            fail InvalidFormatError{"H.265 access unit holds a truncated network abstraction layer unit"}
        return length
    }
}

private func runHevcFrameThread(thread: Threading.Thread)
{
    let frameThread = cast(*HevcFrameThread) thread.userParam!
    while !thread.requestEnd
    {
        frameThread.wake.wait()
        if thread.requestEnd do
            break

        var frame: #null *Frame
        frame = catch frameThread.decoder!.decodePreparedPicture() as decodeError
        if decodeError != null
        {
            frameThread.decoder!.failPreparedPicture()
            frameThread.errorText = Errors.message(decodeError)
        }
        elif frame
        {
            Atomic.exchange(&frame!.heldByCaller, 1)
            frameThread.frame = frame
        }

        frameThread.done.signal()
    }
}
