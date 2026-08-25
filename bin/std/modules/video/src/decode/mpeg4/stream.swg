//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, both the H.263 and MPEG quantisers, and packed bitstreams.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns an indexed track: display order, seeking, and decoding on demand.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors, Pixel

// One picture decoded and waiting for its turn to be shown.
private struct Picture
{
    time:   s64             // Stream time, which is the order pictures are shown in.
    kind:   u32
    planes: PlanarFrame
}

// How many pictures can be held back while their order is settled.
//
// A stream refers forward once and no further: every bidirectional plane follows the plane it
// refers to, so one picture held back is enough to know which comes first. One sample can carry
// two of them, and the answer is emitted after the fill, so four slots cover the widest moment.
private const HeldPictures = 4'u64

// Drives an indexed MPEG-4 Part 2 track independently of its container.
//
// The order a container hands samples over is not the order they are shown in, and a container
// muxed from a format that states no decoding order does not even state the display times: it
// numbers its samples as they are stored. The stream states its own clock, so that is what the
// display order is taken from, and pictures are held back only until their turn is known.
#[Swag.NoCopy]
struct Mpeg4Stream
{
    decoder:      Decoder
    config:       Array'u8
    frames:       Array'SampleEntry     // Samples in decoding order.
    sampleAtRank: Array'u32             // Sample of each display rank, by container time.
    payload:      Array'u8
    prefix:       Array'u8              // Bytes the container took off the front of every stored frame.
    queue:        [HeldPictures] Picture
    queued:       u64
    emitRank:     u64                   // Display rank of the next picture the queue gives up.
    nextRank:     u64                   // Display rank the next call returns.
    nextDecode:   u64                   // Decoding-order sample the decoder is about to read.
    started:      bool
    width:        s32
    height:       s32
}

impl Mpeg4Stream
{
    // Configures the decoder from a container's setup headers and installs the samples.
    mtd open(config: const [..] u8, frames: Array'SampleEntry) fail
    {
        if !@countof(config) do
            fail InvalidFormatError{"MPEG-4 track has no decoder configuration"}

        .config.clear()
        .config.add(config)
        try .decoder.configure(.config.toSlice())
        .width  = cast(s32) .decoder.layer.width
        .height = cast(s32) .decoder.layer.height
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
            while at > 0 and .frames[cast(u64) .sampleAtRank[at - 1]].presentationTime > .frames[index].presentationTime do
                at -= 1
            .sampleAtRank.insertAt(at, cast(u32) index)
        }
    }

    // Installs a window and starts over from its first picture.
    mtd installFrames(frames: Array'SampleEntry)
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
    mtd replaceFrames(frames: Array'SampleEntry) fail
    {
        .installFrames(#move frames)
    }

    // Extends the window with samples the reader has since indexed.
    //
    // Nothing about the decode in flight changes: the added samples are later than every one the
    // decoder has read, so the anchors it holds stay the anchors they were.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        if !@countof(frames) do
            return
        .frames.add(frames)
        .rebuildOrder()
    }

    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        if rank >= .sampleAtRank.count do
            return 0
        return .frames[cast(u64) .sampleAtRank[rank]].presentationTime
    }

    // Returns the first display rank at or before `rank` whose sample starts a clean decode.
    mtd const syncRankAt(rank: u64)->u64
    {
        var scan = Math.min(rank, .sampleAtRank.count)
        while scan > 0
        {
            let sample = cast(u64) .sampleAtRank[scan]
            if sample < .frames.count and .frames[sample].isSync do
                return scan
            scan -= 1
        }

        return 0
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
    }

    // Reads samples until enough pictures are held to know which of them comes first.
    mtd fill(source: *Source) fail
    {
        while .queued < 2 and .nextDecode < .frames.count
        {
            let entry = .frames[.nextDecode]
            try readStoredFrame(source, entry, .prefix.toSlice(), &.payload)
            .nextDecode += 1

            .decoder.beginSample(entry.presentationTime)
            while try .decoder.nextPicture(.payload.toSlice())
            {
                if .queued >= HeldPictures do
                    break
                .decoder.reference().writePlanar(&.queue[.queued].planes)
                .queue[.queued].time = .decoder.pictureTime
                .queue[.queued].kind = .decoder.pictureKind
                .queued += 1
            }
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
    mtd release(at: u64, target: #null *PlanarFrame)
    {
        if let output = target do
            output[] = #move .queue[at].planes
        .queued -= 1
        if at != .queued do
            .queue[at] = #move .queue[.queued]
        .emitRank += 1
    }

    // Decodes forward until the picture of the current rank is reconstructed.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        if .nextRank >= .sampleAtRank.count do
            fail InvalidFormatError{"MPEG-4 stream has no picture at the requested position"}

        // A picture that is not a clean decode point needs everything back to the last one.
        if !.started or .emitRank > .nextRank
        {
            .decoder.reset()
            .queued     = 0
            .emitRank   = .syncRankAt(.nextRank)
            .nextDecode = cast(u64) .sampleAtRank[.emitRank]
            .started    = true
        }

        while true
        {
            try .fill(source)
            if !.queued do
                fail InvalidFormatError{"MPEG-4 stream ends before the picture asked for"}

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
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        var planes: PlanarFrame
        try .decodeNextPlanes(source, &planes)
        planes.view().convertToRgb(target)
    }
}
