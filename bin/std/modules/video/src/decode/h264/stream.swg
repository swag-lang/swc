//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns NAL-unit traversal and emulation-prevention removal.
//
#global namespace H264

using Core, Core.Errors, Pixel

// FFmpeg uses the same automatic ceiling for frame-threaded video decoders.
private const AvcMaxFrameThreads = 16'u32
private const AvcNoLane = Swag.U32.Max

// What one picture in flight costs, and how much the stream may spend on them together.
//
// A frame thread owns a complete picture: its samples, the macroblocks and per-block grids the
// entropy decoder fills, and the reference pictures it still holds. That is about seven bytes
// per pixel, so sixteen threads on a 3840x2160 stream would reserve close to a gigabyte before
// decoding anything. Past a handful of threads the stream already decodes several times faster
// than any clock asks for, so the budget buys back the memory rather than the speed.
private const AvcBytesPerLanePixel = 7'u64
private const AvcLaneMemoryBudget = 640 * 1024 * 1024'u64

// One decoded H.264 frame waiting for its display turn.
private struct PendingFrame
{
    frame: #null *H264.Frame
    rank:  u64
}

// Ownership state of one complete per-frame decoder context.
private enum AvcLaneState
{
    Free
    Decoding
}

// One persistent frame thread. Its decoder owns every per-picture CABAC, macroblock, residual,
// motion, reconstruction, and deblocking state until the owner joins the result.
#[Swag.NoCopy]
struct AvcFrameThread
{
    thread:    Threading.Thread
    wake:      Sync.Event
    done:      Sync.Event
    decoder:   #null *H264.Decoder
    frame:     #null *H264.Frame
    errorText: String
}

// One decode-order frame thread waiting to be joined by the output owner.
private struct ThreadedAvcSample
{
    lane: u32
    rank: u64
}

// One reconstructed frame paired with its display rank.
private struct DecodedAvcSample
{
    frame: *H264.Frame
    rank:  u64
}

// Drives an indexed H.264 stream independently of its container.
//
// Up to sixteen complete decoder contexts run pictures concurrently. The owner publishes the
// prediction setup of picture N before its CABAC data starts, immediately prepares N+1 from that
// state, then starts one frame job per context. A frame job waits only when reconstruction needs
// pixels from an earlier reference picture. Stored decode order is joined before display order is
// resolved, so the public reader contract remains deterministic.
struct AvcStream
{
    decoders:     [AvcMaxFrameThreads] H264.Decoder
    frameThreads: [AvcMaxFrameThreads] AvcFrameThread
    payloads:     [AvcMaxFrameThreads] Array'u8
    laneStates:   [AvcMaxFrameThreads] AvcLaneState
    threaded:     [AvcMaxFrameThreads] ThreadedAvcSample
    frames:       Array'SampleEntry     // Samples in decode order.
    rankOfSample: Array'u32             // Display rank of each decode-order sample.
    sampleAtRank: Array'u32             // Decode-order sample of each display rank.
    syncFlags:    Array'u8              // Whether each sample starts a clean decode.
    assumedSync:  bool                  // The first sample was taken to start one for want of any mark.
    positioned:   bool                  // A position was chosen rather than merely assumed.
    pending:      Array'PendingFrame

    threadedHead:      u32
    threadedTail:      u32
    threadedCount:     u32
    threadedHighWater: u32
    laneCount:         u32 = 1
    lastSetupLane:     u32 = AvcNoLane
    threadsStarted:    bool
    reachedEnd:        bool
    skipBefore:        u64
    decodeLimit:       u64 = Swag.U64.Max     // Exclusive decode-order ceiling during seek preroll.
    nextDecode:        u64     // Next sample to hand a frame context.
    nextRank:          u64     // Display rank the next decode call returns.
    width:             s32
    height:            s32
    cropLeft:          s32
    cropTop:           s32
}

impl AvcStream
{
    // Configures every decoder context and builds the display-order tables.
    mtd open(config: const [..] u8, frames: Array'SampleEntry) fail
    {
        if !@countof(config) do
            fail InvalidFormatError{"H.264 track has no decoder configuration"}
        for &decoder in .decoders do
            decoder.configure(config)

        .laneCount = Math.max(1'u32, Math.min(Jobs.workerCount(), AvcMaxFrameThreads))
        let sps = .decoders[0].firstSps()
        if !sps do
            fail InvalidFormatError{"H.264 decoder configuration has no sequence parameter set"}
        .width    = sps.width()
        .height   = sps.height()
        .cropLeft = sps.cropLeft
        .cropTop  = sps.cropTop

        let laneBytes = cast(u64) sps.mbWidth * cast(u64) sps.mbHeight * 256 * AvcBytesPerLanePixel
        if laneBytes do
            .laneCount = Math.max(1'u32, Math.min(.laneCount, cast(u32) Math.max(AvcLaneMemoryBudget / laneBytes, 1'u64)))

        .installFrames(#move frames)
    }

    // Replaces the container window while retaining the configured decoder contexts.
    // The first sample must start a clean decode, as it does after a Matroska cue seek.
    mtd replaceFrames(frames: Array'SampleEntry) fail
    {
        .stopFrameThreads()
        .releasePending()
        .clearFrameThreads()
        for &decoder in .decoders do
            decoder.restart()

        .nextDecode = 0
        .nextRank   = 0
        .skipBefore = 0
        .decodeLimit = Swag.U64.Max
        .reachedEnd = false
        .positioned = false
        .installFrames(#move frames)
    }

    private mtd installFrames(frames: Array'SampleEntry) fail
    {
        .frames = #move frames
        let count = .frames.count

        // Display ranks: stable order of the composition times. Real streams are already
        // nearly sorted, off by at most the reorder depth, so an insertion pass is linear.
        var order: Array'u32
        order.reserve(count)
        for index in count
        {
            var position = order.count
            while position > 0 and .frames[cast(u64) order[position - 1]].presentationTime > .frames[index].presentationTime
            {
                position -= 1
            }

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
        var marked = false
        for index in count where .frames[index].isSync
        {
            .syncFlags[index] = 1
            marked = true
        }

        // A container that marks nothing says nothing, and the first sample is then the only place
        // a decode can start. One that marks something is believed about the rest: a stream clipped
        // in the middle of a group has no clean start before its first marked sample, and assuming
        // one there decodes slices whose references were cut away with the file they came from.
        .assumedSync = count != 0 and !marked
        if .assumedSync do
            .syncFlags[0] = 1
    }

    // Extends a running stream and merges presentation order beyond the consumed prefix.
    //
    // Container chunks are decode-order boundaries, not presentation-order boundaries: B-frames
    // from a new chunk can precede the tail of the previous one. Ranks already returned remain
    // fixed. The live decode pipeline continues when the insertion is beyond every sample already
    // handed to it; only an overlap with in-flight work requires a restart from the preceding sync.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        if !@countof(frames) do
            return
        if @countof(frames) > Swag.U32.Max - .frames.count do
            fail OverflowError{"H.264 video sample table is too large"}

        let first = .frames.count
        var order: Array'u32
        order.reserve(@countof(frames))
        for index in @countof(frames)
        {
            var position = order.count
            while position > 0 and frames[cast(u64) order[position - 1]].presentationTime > frames[index].presentationTime
            {
                position -= 1
            }

            order.insertAt(position, cast(u32) index)
        }

        let mutableRank = Math.min(.nextRank, .sampleAtRank.count)
        if mutableRank and frames[cast(u64) order[0]].presentationTime < .presentationTimeAtRank(mutableRank - 1) do
            fail InvalidFormatError{"H.264 container chunk overlaps pictures already presented"}

        let firstNewTimestamp = frames[cast(u64) order[0]].presentationTime
        var insertionRank     = mutableRank
        while insertionRank < first and .presentationTimeAtRank(insertionRank) <= firstNewTimestamp do
            insertionRank += 1

        var stableRank = mutableRank
        for sample in Math.min(.nextDecode, first) do
            stableRank = Math.max(stableRank, cast(u64) .rankOfSample[sample] + 1)
        let restart = insertionRank < stableRank

        var merged: Array'u32
        merged.reserve(first + @countof(frames))
        if mutableRank do
            merged.add(.sampleAtRank.toSlice()[0 until mutableRank])

        var oldRank = mutableRank
        var newRank = 0'u64
        while oldRank < first or newRank < order.count
        {
            let useOld = newRank >= order.count or (oldRank < first and .presentationTimeAtRank(oldRank) <= frames[cast(u64) order[newRank]].presentationTime)
            if useOld
            {
                merged.add(.sampleAtRank[oldRank])
                oldRank += 1
            }
            else
            {
                merged.add(cast(u32) (first + cast(u64) order[newRank]))
                newRank += 1
            }
        }

        if restart
        {
            .stopFrameThreads()
            .releasePending()
            .clearFrameThreads()
            for &decoder in .decoders do
                decoder.restart()
        }

        .frames.add(frames)
        .syncFlags.resize(.frames.count)
        for localSample in @countof(frames)
        {
            let sample = first + localSample
            if .frames[sample].isSync do
                .syncFlags[sample] = 1
        }

        // A first sample taken to start a clean decode only because nothing said otherwise gives
        // that up as soon as the container marks one it does mark.
        if .assumedSync
        {
            for localSample in @countof(frames) where frames[localSample].isSync
            {
                .syncFlags[0] = cast(u8) (.frames[0].isSync ? 1 : 0)
                .assumedSync  = false
                break
            }
        }

        .sampleAtRank = #move merged
        .rankOfSample.resize(.frames.count)
        for rank in mutableRank until .sampleAtRank.count do
            .rankOfSample[cast(u64) .sampleAtRank[rank]] = cast(u32) rank

        .reachedEnd = false
        if !restart do
            return

        let nextSample = cast(u64) .sampleAtRank[.nextRank]
        var sync       = nextSample
        while sync > 0 and .syncFlags[sync] == 0 do
            sync -= 1
        .nextDecode = sync
        .skipBefore = .nextRank
    }

    mtd opDrop()
    {
        .stopFrameThreads()
        .releasePending()
        .clearFrameThreads()
        .shutdownFrameThreads()
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    // Returns the stream length when no sync sample remains past `rank`.
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
        // The position a stream starts at is an assumption until it is worked out here, and a
        // stream clipped in the middle of a group does not start where it says it does.
        if rank == .nextRank and .positioned do
            return

        .stopFrameThreads()
        var wanted = rank
        var sample = cast(u64) .sampleAtRank[wanted]
        var sync   = sample
        while sync > 0 and .syncFlags[sync] == 0 do
            sync -= 1

        // A stream that begins in the middle of a group holds no picture standing on its own
        // before its first sync point: the pictures ahead of it were cut away with the file they
        // came from, and the earliest one this stream can answer with is that sync point itself.
        if .syncFlags[sync] == 0
        {
            let first = .syncRankAt(wanted)
            if first < .frames.count
            {
                wanted = first
                sample = cast(u64) .sampleAtRank[wanted]
                sync   = sample
            }
        }

        var alreadyPending = false
        for entry in .pending where entry.rank == wanted
        {
            alreadyPending = true
            break
        }

        if wanted < .nextRank or (!alreadyPending and sync > .nextDecode)
        {
            .releasePending()
            .clearFrameThreads()
            for &decoder in .decoders do
                decoder.restart()
            .nextDecode = sync
            .reachedEnd = false
        }
        else
        {
            .releasePendingBelow(wanted)
        }

        .skipBefore  = wanted
        .decodeLimit = sample + 1
        .nextRank    = wanted
        .positioned  = true
    }

    // Releases every pending frame whose display rank precedes `rank`.
    mtd releasePendingBelow(rank: u64)
    {
        var index = 0'u64
        while index < .pending.count
        {
            if .pending[index].rank < rank
            {
                .decoders[0].releaseFrame(.pending[index].frame!)
                .pending.removeAt(index)
                continue
            }

            index += 1
        }
    }

    // Waits for every queued frame context in dependency order.
    mtd stopFrameThreads()
    {
        var index = .threadedHead
        for .threadedCount
        {
            let lane = .threaded[index].lane
            .frameThreads[lane].done.wait()
            index = (index + 1) % AvcMaxFrameThreads
        }
    }

    // Creates dedicated persistent frame owners. They stay outside the shared job pool so their
    // reconstruction and deblocking passes can use every job worker without nested-job starvation.
    //
    // They also run below normal priority. Frame threading deliberately decodes far ahead of
    // whatever consumes the pictures, so a lane is almost always working on something that is
    // not needed yet; at these resolutions there are enough of them to keep a consumer that
    // has to present on a clock off the processor, and a decoder that races ahead while the
    // picture on screen stutters has won nothing.
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
            frameThread.thread.init(&runAvcFrameThread, frameThread, priority: .BelowNormal)
            frameThread.thread.start()
        }

        .threadsStarted = true
    }

    // Stops the persistent frame owners and releases their synchronization handles.
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

    // Releases queued results and returns every decoder context to the free set.
    mtd clearFrameThreads()
    {
        var index = .threadedHead
        for .threadedCount
        {
            let lane        = .threaded[index].lane
            let frameThread = &.frameThreads[lane]
            if frameThread.frame do
                .decoders[lane].releaseFrame(frameThread.frame!)
            frameThread.frame = null
            .decoders[lane].discardAccessUnit()
            .laneStates[lane] = .Free
            index             = (index + 1) % AvcMaxFrameThreads
        }

        .threadedHead  = 0
        .threadedTail  = 0
        .threadedCount = 0
        .lastSetupLane = AvcNoLane
    }

    // Reserves a context without destroying the newest published prediction state.
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

        return AvcNoLane
    }

    // Prepares and starts one complete frame thread.
    private mtd startFrame(source: *Source)->bool fail
    {
        let lane = .reserveLane()
        if lane == AvcNoLane do
            return false

        let decoder = &.decoders[lane]
        if .lastSetupLane != AvcNoLane and lane != .lastSetupLane do
            decoder.inheritPredictionState(&.decoders[.lastSetupLane])

        let payload = &.payloads[lane]
        while .nextDecode < .frames.count and .nextDecode < .decodeLimit
        {
            let entry = .frames[.nextDecode]
            if payload.count != entry.size do
                payload.resize(entry.size)
            source.seek(entry.offset)
            source.readExact(payload.toSlice())

            let rank = cast(u64) .rankOfSample[.nextDecode]
            .nextDecode += 1
            if rank < .skipBefore and decoder.canSkipWhileSeeking(payload.toSlice()) do
                continue
            if !try decoder.prepareAccessUnit(payload.toSlice()) do
                fail InvalidFormatError{"H.264 access unit carries no picture"}

            let frameThread = &.frameThreads[lane]
            frameThread.decoder   = decoder
            frameThread.frame     = null
            frameThread.errorText = ""
            frameThread.done.reset()

            .threaded[.threadedTail] = {lane, rank}
            .threadedTail            = (.threadedTail + 1) % AvcMaxFrameThreads
            .threadedCount           += 1
            if .threadedCount > .threadedHighWater do
                .threadedHighWater = .threadedCount
            .lastSetupLane = lane

            frameThread.wake.signal()
            return true
        }

        .laneStates[lane] = .Free
        if .nextDecode >= .decodeLimit do
            return false

        .reachedEnd = true
        return false
    }

    // Keeps every automatic frame context busy.
    private mtd fillFrameThreads(source: *Source) fail
    {
        .ensureFrameThreads()
        while .threadedCount < .laneCount and !.reachedEnd
        {
            if !try .startFrame(source) do
                break
        }
    }

    // Joins the oldest frame thread and immediately reuses its context for future setup.
    mtd decodeStoredSample(source: *Source)->DecodedAvcSample fail
    {
        .fillFrameThreads(source)
        if .threadedCount == 0 do
            fail InvalidFormatError{"H.264 stream ends before the requested frame"}

        let threaded = .threaded[.threadedHead]
        .threadedHead  = (.threadedHead + 1) % AvcMaxFrameThreads
        .threadedCount -= 1

        let frameThread = &.frameThreads[threaded.lane]
        frameThread.done.wait()
        if frameThread.errorText.length do
            fail InvalidFormatError{Errors.mkString(frameThread.errorText.toString())}
        if !frameThread.frame do
            fail InvalidFormatError{"H.264 access unit carries no picture"}

        let frame = frameThread.frame!
        frameThread.frame          = null
        .laneStates[threaded.lane] = .Free
        .fillFrameThreads(source)
        return {frame, threaded.rank}
    }

    // Decodes until the frame with the current display rank exists, and returns it.
    //
    // The caller owns the result for the length of one call and must release it.
    private mtd nextDisplayFrame(source: *Source)->*H264.Frame fail
    {
        let wanted = .nextRank
        while true
        {
            for index in .pending.count where .pending[index].rank == wanted
            {
                let frame = .pending[index].frame!
                .pending.removeAt(index)
                .nextRank    = wanted + 1
                .decodeLimit = Swag.U64.Max
                return frame
            }

            if .threadedCount == 0 and .reachedEnd do
                fail InvalidFormatError{"H.264 stream ends before the requested frame"}

            let decoded = try .decodeStoredSample(source)
            if decoded.rank < wanted
            {
                .decoders[0].releaseFrame(decoded.frame)
                continue
            }

            .pending.add({decoded.frame, decoded.rank})
            if .pending.count > 34 do
                fail InvalidFormatError{"H.264 stream reorders more than 34 frames"}
        }
    }

    // Decodes the frame with the current display rank and converts it to RGB.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        let frame = try .nextDisplayFrame(source)
        frame.toRgb(target, .width, .height, .cropLeft, .cropTop)
        .decoders[0].releaseFrame(frame)
    }

    // Decodes the frame with the current display rank and hands over its planes unconverted.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        let frame = try .nextDisplayFrame(source)
        frame.copyPlanes(target, .width, .height, .cropLeft, .cropTop)
        .decoders[0].releaseFrame(frame)
    }

    // Releases every frame waiting for display.
    mtd releasePending()
    {
        for entry in .pending do
            .decoders[0].releaseFrame(entry.frame!)
        .pending.clear()
    }
}

// Decodes complete pictures in one persistent per-frame context.
private func runAvcFrameThread(thread: Threading.Thread)
{
    let frameThread = cast(*AvcFrameThread) thread.userParam!
    while !thread.requestEnd
    {
        frameThread.wake.wait()
        if thread.requestEnd do
            break

        var frame: #null *H264.Frame
        frame = catch frameThread.decoder!.decodePreparedAccessUnit() as decodeError
        if decodeError != null
        {
            frameThread.decoder!.failPreparedAccessUnit()
            frameThread.errorText = Errors.message(decodeError)
        }
        else do
            frameThread.frame = frame

        frameThread.done.signal()
    }
}
