#global namespace Mp4

using Core, Core.Errors, Pixel

// One decoded H.264 frame waiting for its display turn.
private struct PendingFrame
{
    frame: #null *H264.Frame
    rank:  u64
}

// One access-unit parser running ahead of picture reconstruction.
struct AvcParseJob
{
    using base: Jobs.Job

    decoder:    #null *H264.Decoder
    payload:    #null *Array'u8
    errorText:  String
    started:    u32
    hasPicture: bool
    scheduled:  bool
}

// One reconstructed frame paired with its display rank.
private struct DecodedAvcSample
{
    frame: *H264.Frame
    rank:  u64
}

// Drives the H.264 track of an ISO-BMFF stream.
//
// The container knows each sample's display time, so display ordering lives here rather than
// in the decoder: samples are fed in stored decode order, and every decoded frame waits in a
// small pending set until its display rank is the one the caller asked for. Seeking backward
// restarts at the nearest sync sample at or before the target and decodes forward, dropping
// the frames that only exist to rebuild the references.
struct AvcStream
{
    decoders:     [2] H264.Decoder
    frames:       Array'FrameEntry     // Sample offsets and sizes, in decode order.
    rankOfSample: Array'u32            // Display rank of each decode-order sample.
    sampleAtRank: Array'u32            // Decode-order sample of each display rank.
    syncFlags:    Array'u8             // Whether each sample starts a clean decode.
    pending:      Array'PendingFrame
    payloads:     [2] Array'u8
    parseJobs:    [2] AvcParseJob
    parsedLane:   u32
    parsedRank:   u64
    hasParsed:    bool
    nextDecode:   u64     // Next sample to hand the decoder.
    nextRank:     u64     // Display rank the next decode call returns.
    width:        s32
    height:       s32
    cropLeft:     s32
    cropTop:      s32
}

impl AvcStream
{
    // Configures the decoder from the track and builds the display-order tables.
    mtd open(track: *Track, frames: Array'FrameEntry) fail
    {
        if !track.avcConfig.count do
            fail InvalidFormatError{"MP4 AVC track has no decoder configuration"}
        .decoders[0].configure(track.avcConfig.toSlice())
        .decoders[1].configure(track.avcConfig.toSlice())

        let sps = .decoders[0].firstSps()
        if !sps do
            fail InvalidFormatError{"MP4 AVC configuration carries no sequence parameter set"}
        .width    = sps.width()
        .height   = sps.height()
        .cropLeft = sps.cropLeft
        .cropTop  = sps.cropTop

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

        // A stream whose first sample is not marked as a seek point still has to start
        // somewhere.
        if count do
            .syncFlags[0] = 1
        .nextDecode = 0
        .nextRank   = 0
    }

    mtd opDrop()
    {
        .stopParse()
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    //
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

        // A forward jump also restarts when its preceding sync sample is ahead of the current
        // decode position. This avoids decoding an ever-growing prefix while scrubbing.
        if rank < .nextRank or (!alreadyPending and sync > .nextDecode)
        {
            .stopParse()
            .releasePending()
            for &decoder in .decoders do
                decoder.restart()
            .hasParsed  = false
            .nextDecode = sync
        }
        else
        {
            // Ranks jumped over will never be requested again; holding their frames would
            // starve the decoder's frame pool over a long playback.
            .releasePendingBelow(rank)
        }

        .nextRank = rank
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

    // Waits for and forgets an access-unit parse that the caller no longer needs.
    mtd stopParse()
    {
        if !.hasParsed do
            return

        let job = &.parseJobs[.parsedLane]
        if job.scheduled do
            Jobs.wait(job)
        job.scheduled = false
        .hasParsed    = false
    }

    // Waits until the selected lane has parsed its access unit.
    mtd waitParse() fail
    {
        let job = &.parseJobs[.parsedLane]
        if job.scheduled do
            Jobs.wait(job)
        job.scheduled = false

        if job.errorText.length do
            fail InvalidFormatError{Errors.mkString(job.errorText.toString())}
        if !job.hasPicture do
            fail InvalidFormatError{"MP4 video sample carries no picture"}
    }

    // Reads and starts the next access unit that cannot be omitted for `wanted`.
    mtd startParse(source: *Source, lane: u32, wanted: u64, previous: #null *H264.Decoder, asynchronous: bool)->bool fail
    {
        let decoder = &.decoders[lane]
        if previous do
            decoder.inheritPredictionState(previous!)

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
            if rank < wanted and decoder.canSkipWhileSeeking(payload.toSlice()) do
                continue

            let job = &.parseJobs[lane]
            job.decoder    = decoder
            job.payload    = payload
            job.errorText  = ""
            job.started    = 0
            job.hasPicture = false
            job.scheduled  = asynchronous

            .parsedLane = lane
            .parsedRank = rank
            .hasParsed  = true
            if asynchronous
            {
                job.lambda = &runAvcParse
                job.data   = job
                Jobs.schedule(job)

                // Starting the entropy parser before reconstruction fans out prevents the
                // scheduler's LIFO queue from burying it under the reconstruction bands.
                while Atomic.get(&job.started) == 0 do
                    Threading.Thread.yield()
            }
            else do
                runAvcParse(job)
            return true
        }

        .hasParsed = false
        return false
    }

    // Reconstructs the next decode-order sample while parsing its successor on another lane.
    mtd decodeStoredSample(source: *Source, wanted: u64)->DecodedAvcSample fail
    {
        if !.hasParsed
        {
            if !try .startParse(source, 0, wanted, null, false) do
                fail InvalidFormatError{"MP4 stream ends before the requested frame"}
        }

        .waitParse()
        let lane    = .parsedLane
        let rank    = .parsedRank
        let decoder = &.decoders[lane]
        .hasParsed = false

        // Two scheduler workers are the minimum useful pipeline: one parses while the caller
        // and the remaining workers reconstruct the preceding picture.
        if Jobs.workerCount() > 1 do
            discard try .startParse(source, 1 - lane, wanted, decoder, true)

        let frame = try decoder.finishAccessUnit()
        return {frame, rank}
    }

    // Decodes until the frame with the current display rank exists, then emits it.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        let wanted = .nextRank
        while true
        {
            // A frame decoded earlier may already be waiting.
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

            if !.hasParsed and .nextDecode >= .frames.count do
                fail InvalidFormatError{"MP4 stream ends before the requested frame"}

            let decoded = try .decodeStoredSample(source, wanted)
            if decoded.rank < wanted
            {
                // Only decoded to rebuild the reference chain.
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

// Parses one complete access unit on a scheduler worker.
private func runAvcParse(data: #null *void)
{
    let job = cast(*AvcParseJob) data!
    Atomic.exchange(&job.started, 1)
    let hasPicture = catch job.decoder!.parseAccessUnit(job.payload!.toSlice(), true) as parseError
    if parseError != null
    {
        job.errorText = Errors.message(parseError)
        return
    }

    job.hasPicture = hasPicture
}
