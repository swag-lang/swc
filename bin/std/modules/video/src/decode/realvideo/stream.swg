#global namespace RealVideo
#global internal

using Core, Core.Errors, Pixel

// One picture decoded and waiting for its turn to be shown.
private struct Picture
{
    time:   s64     // Stream time, which is the order pictures are shown in.
    planes: PlanarFrame
}

// One reference waits while the following B pictures are emitted.
private const HeldPictures = 2'u64

// Drives an indexed RealVideo 4 track independently of its container.
//
// The container corrects legacy timestamps from the RV40 clock before handing over samples.
// Reference pictures arrive before their dependent B pictures and wait for their display turn.
#[Swag.NoCopy]
struct Stream
{
    decoder:      Decoder
    config:       Array'u8
    frames:       Array'SampleEntry     // Samples in decoding order.
    sampleAtRank: Array'u32             // Sample of each display rank, by container time.
    payload:      Array'u8
    prefix:       Array'u8     // Bytes the container took off the front of every stored frame.
    queue:        [HeldPictures] Picture
    queued:       u64
    emitRank:     u64     // Display rank of the next picture the queue gives up.
    nextRank:     u64     // Display rank the next call returns.
    nextDecode:   u64     // Decoding-order sample the decoder is about to read.
    startTime:    s64     // Pictures before this sync point need references outside the window.
    started:      bool
    width:        s32
    height:       s32
}

impl Stream
{
    // Configures the decoder from a container's setup headers and installs the samples.
    mtd open(config: const [..] u8, frames: #move Array'SampleEntry) fail
    {
        if not config.count do
            fail InvalidFormatError{"RealVideo track has no decoder configuration"}

        .config.clear()
        .config.add(config)
        let size = try configurationSize(.config.toSlice())
        .width  = size.width
        .height = size.height
        try .decoder.configure(.width, .height)
        .installFrames(#move frames)
    }

    // Builds the display order of the window the container holds.
    //
    // A container that indexes progressively hands more samples over as it reads, and every
    // sample it adds is later than the ones already there, so the order of those does not move.
    // Rebuilding it must therefore not disturb a decode already in flight.
    mtd rebuildOrder()
    {
        .sampleAtRank.clear()
        .sampleAtRank.reserve(.frames.count)

        // A stable insertion by presentation time: the tables are short, and equal times must
        // keep the order the container stated.
        for index in .frames.count
        {
            var at = .sampleAtRank.count
            while at > 0 and .frames[cast(u64, .sampleAtRank[at - 1])].presentationTime > .frames[index].presentationTime do
                at -= 1
            .sampleAtRank.insertAt(at, cast(u32, index))
        }
    }

    // Installs a window and starts over from its first picture.
    mtd installFrames(frames: #move Array'SampleEntry)
    {
        .frames = #move frames
        .rebuildOrder()
        .nextRank   = 0
        .nextDecode = 0
        .started    = false
        .queued     = 0
        .decoder.reset()
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: #move Array'SampleEntry) fail
    {
        .installFrames(#move frames)
    }

    // Extends the window with samples the reader has since indexed.
    //
    // Nothing about the decode in flight changes: the added samples are later than every one the
    // decoder has read, so the anchors it holds stay the anchors they were.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        if not frames.count do
            return
        .frames.add(frames)
        .rebuildOrder()
    }

    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        if rank >= .sampleAtRank.count do
            return 0
        return .frames[cast(u64, .sampleAtRank[rank])].presentationTime
    }

    mtd const isSyncRank(rank: u64)->bool
    {
        let sample = cast(u64, .sampleAtRank[rank])
        return sample < .frames.count and .frames[sample].isSync
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    // Returns the stream length when no sync sample remains past `rank`.
    mtd const syncRankAt(rank: u64)->u64
    {
        var scan = rank
        while scan < .sampleAtRank.count and not .isSyncRank(scan) do
            scan += 1
        return Math.min(scan, .sampleAtRank.count)
    }

    // Returns the last display rank at or before `rank` whose sample starts a clean decode,
    // which is where decoding the picture of `rank` has to begin.
    mtd const decodeStartRank(rank: u64)->u64
    {
        if not .sampleAtRank.count do
            return 0
        var scan = Math.min(rank, .sampleAtRank.count - 1)
        while scan > 0 and not .isSyncRank(scan) do
            scan -= 1
        return scan
    }

    // Positions the stream so the next decoded picture has display rank `rank`.
    mtd seekTo(rank: u64)
    {
        if rank == .nextRank do
            return
        .nextRank = rank
        .started  = false
    }

    mtd releasePending()
    {
        .queued  = 0
        .started = false
        for &picture in .queue do
            picture.planes = {}
    }

    // Reads samples until enough pictures are held to know which of them comes first.
    mtd fill(source: *ByteSource) fail
    {
        while .queued < 2 and .nextDecode < .frames.count
        {
            let entry = .frames[.nextDecode]
            .nextDecode += 1

            // An open group can store earlier B pictures immediately after its I picture.
            // Seeking starts at that I picture; those B pictures belong to the previous group.
            if entry.presentationTime < .startTime do
                continue
            try readStoredFrame(source, entry, .prefix.toSlice(), &.payload)

            try .decoder.decode(.payload.toSlice(), &.queue[.queued].planes)
            .queue[.queued].time = entry.presentationTime
            .queued += 1
        }
    }

    // Which held picture is shown first.
    mtd const earliest()->u64
    {
        var at = 0'u64
        for index in .queued where .queue[index].time < .queue[at].time do
            at = index
        return at
    }

    // Gives up one held picture, either to the caller or to the floor.
    mtd release(at: u64, target: *PlanarFrame?)
    {
        if let output = target do
            output[] = #move .queue[at].planes
        .queued -= 1
        if at != .queued do
            .queue[at] = #move .queue[.queued]
        .emitRank += 1
    }

    // Decodes forward until the picture of the current rank is reconstructed.
    mtd decodeNextPlanes(source: *ByteSource, target: *PlanarFrame) fail
    {
        if .nextRank >= .sampleAtRank.count do
            fail InvalidFormatError{"RealVideo stream has no picture at the requested position"}

        // A picture that is not a clean decode point needs everything back to the last one.
        if not .started or .emitRank > .nextRank
        {
            .decoder.reset()
            .queued     = 0
            .emitRank   = .decodeStartRank(.nextRank)
            .nextDecode = cast(u64, .sampleAtRank[.emitRank])
            .startTime  = .frames[.nextDecode].presentationTime
            .started    = true
        }

        while true
        {
            try .fill(source)
            if not .queued do
                fail InvalidFormatError{"RealVideo stream ends before the picture asked for"}

            let at = .earliest()
            if .emitRank == .nextRank
            {
                .release(at, target)
                .nextRank += 1
                return
            }

            // A picture shown before the one asked for is decoded for what it anchors, not for
            // itself.
            .release(at, null)
        }
    }

    // Decodes the picture of the current rank and converts it to packed colour.
    mtd decodeNext(source: *ByteSource, target: *Image) fail
    {
        var planes: PlanarFrame
        try .decodeNextPlanes(source, &planes)
        planes.view().convertToRgb(target)
    }
}
