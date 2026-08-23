#global namespace Mp4

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

// Drives the H.264 track of an ISO-BMFF stream.
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
    frames:       Array'FrameEntry     // Sample offsets and sizes, in decode order.
    rankOfSample: Array'u32            // Display rank of each decode-order sample.
    sampleAtRank: Array'u32            // Decode-order sample of each display rank.
    syncFlags:    Array'u8             // Whether each sample starts a clean decode.
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
    mtd open(track: *Track, frames: Array'FrameEntry) fail
    {
        if !track.avcConfig.count do
            fail InvalidFormatError{"MP4 AVC track has no decoder configuration"}
        for &decoder in .decoders do
            decoder.configure(track.avcConfig.toSlice())

        .laneCount = Math.max(1'u32, Math.min(Jobs.workerCount(), AvcMaxFrameThreads))
        let sps = .decoders[0].firstSps()
        if !sps do
            fail InvalidFormatError{"MP4 AVC configuration carries no sequence parameter set"}
        .width    = sps.width()
        .height   = sps.height()
        .cropLeft = sps.cropLeft
        .cropTop  = sps.cropTop

        let laneBytes = cast(u64) sps.mbWidth * cast(u64) sps.mbHeight * 256 * AvcBytesPerLanePixel
        if laneBytes do
            .laneCount = Math.max(1'u32, Math.min(.laneCount, cast(u32) Math.max(AvcLaneMemoryBudget / laneBytes, 1'u64)))

        .frames = #move frames
        let count = .frames.count

        // Display ranks: stable order of the composition times. Real streams are already
        // nearly sorted, off by at most the reorder depth, so an insertion pass is linear.
        let times = track.sampleTimes()
        var order: Array'u32
        order.reserve(count)
        for index in count
        {
            var position = order.count
            while position > 0 and times[cast(u64) order[position - 1]] > times[index]
            {
                position -= 1
            }

            order.insertAt(position, cast(u32) index)
        }

        .rankOfSample.resize(count)
        .sampleAtRank.resize(count)
        for rank in order.count
        {
            .sampleAtRank[rank] = order[rank]
            .rankOfSample[cast(u64) order[rank]] = cast(u32) rank
        }

        .syncFlags.resize(count)
        if track.syncSamples.count
        {
            for sample in track.syncSamples
            {
                if cast(u64) sample < count do
                    .syncFlags[cast(u64) sample] = 1
            }
        }
        else
        {
            for index in count do
                .syncFlags[index] = 1
        }

        if count do
            .syncFlags[0] = 1
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

        if rank < .nextRank or (!alreadyPending and sync > .nextDecode)
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
            .releasePendingBelow(rank)
        }

        .skipBefore = rank
        .nextRank   = rank
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
        while .nextDecode < .frames.count
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
                fail InvalidFormatError{"MP4 video sample carries no picture"}

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
        .reachedEnd       = true
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
            fail InvalidFormatError{"MP4 stream ends before the requested frame"}

        let threaded = .threaded[.threadedHead]
        .threadedHead  = (.threadedHead + 1) % AvcMaxFrameThreads
        .threadedCount -= 1

        let frameThread = &.frameThreads[threaded.lane]
        frameThread.done.wait()
        if frameThread.errorText.length do
            fail InvalidFormatError{Errors.mkString(frameThread.errorText.toString())}
        if !frameThread.frame do
            fail InvalidFormatError{"MP4 video sample carries no picture"}

        let frame = frameThread.frame!
        frameThread.frame          = null
        .laneStates[threaded.lane] = .Free
        .fillFrameThreads(source)
        return {frame, threaded.rank}
    }

    // Decodes until the frame with the current display rank exists, then emits it.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        let wanted = .nextRank
        while true
        {
            var found = false
            for index in .pending.count where .pending[index].rank == wanted
            {
                let frame = .pending[index].frame!
                frame.toRgb(target, .width, .height, .cropLeft, .cropTop)
                .decoders[0].releaseFrame(frame)
                .pending.removeAt(index)
                found = true
                break
            }

            if found do
                break
            if .threadedCount == 0 and .reachedEnd do
                fail InvalidFormatError{"MP4 stream ends before the requested frame"}

            let decoded = try .decodeStoredSample(source)
            if decoded.rank < wanted
            {
                .decoders[0].releaseFrame(decoded.frame)
                continue
            }

            .pending.add({decoded.frame, decoded.rank})
            if .pending.count > 34 do
                fail InvalidFormatError{"MP4 stream reorders more frames than a valid stream can"}
        }

        .nextRank = wanted + 1
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
