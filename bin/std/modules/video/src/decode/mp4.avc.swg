#global namespace Mp4

using Core, Core.Errors, Pixel

// One decoded H.264 frame waiting for its display turn.
private struct PendingFrame
{
    frame: #null *H264.Frame
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
    decoder:      H264.Decoder
    frames:       Array'FrameEntry     // Sample offsets and sizes, in decode order.
    rankOfSample: Array'u32            // Display rank of each decode-order sample.
    sampleAtRank: Array'u32            // Decode-order sample of each display rank.
    syncFlags:    Array'u8             // Whether each sample starts a clean decode.
    pending:      Array'PendingFrame
    payload:      Array'u8
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
        .decoder.configure(track.avcConfig.toSlice())

        let sps = .decoder.firstSps()
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
            .releasePending()
            .decoder.restart()
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
                .decoder.releaseFrame(.pending[index].frame!)
                .pending.removeAt(index)
                continue
            }

            index += 1
        }
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
                .decoder.releaseFrame(frame)
                .pending.removeAt(index)
                found = true
                break
            }

            if found do
                break

            if .nextDecode >= .frames.count do
                fail InvalidFormatError{"MP4 stream ends before the requested frame"}

            let entry = .frames[.nextDecode]
            if .payload.count != entry.size do
                .payload.resize(entry.size)
            source.seek(entry.offset)
            source.readExact(.payload.toSlice())

            let decoded = .decoder.decodeAccessUnit(.payload.toSlice())
            if !decoded do
                fail InvalidFormatError{"MP4 video sample carries no picture"}

            let rank = cast(u64) .rankOfSample[.nextDecode]
            .nextDecode += 1
            if rank < wanted
            {
                // Only decoded to rebuild the reference chain.
                .decoder.releaseFrame(decoded!)
                continue
            }

            .pending.add({decoded, rank})
            if .pending.count > 34 do
                fail InvalidFormatError{"MP4 stream reorders more frames than a valid stream can"}
        }

        .nextRank = wanted + 1
    }

    // Releases every frame waiting for display.
    mtd releasePending()
    {
        for entry in .pending do
            .decoder.releaseFrame(entry.frame!)
        .pending.clear()
    }
}
