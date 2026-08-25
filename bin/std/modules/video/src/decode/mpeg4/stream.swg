//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns an indexed track: display order, seeking, and decoding on demand.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors, Pixel

// Drives an indexed MPEG-4 Part 2 track independently of its container.
//
// A stream with bidirectional planes stores them after the plane they refer forward to, so the
// order a container hands samples over is not the order they are shown in. The container states
// when each is shown, and that is what the display order is built from.
#[Swag.NoCopy]
struct Mpeg4Stream
{
    decoder:      Decoder
    config:       Array'u8
    frames:       Array'SampleEntry     // Samples in decoding order.
    sampleAtRank: Array'u32             // Decoding-order sample of each display rank.
    payload:      Array'u8
    nextRank:     u64                   // Display rank the next call returns.
    nextDecode:   u64                   // Decoding-order sample the decoder is about to read.
    started:      bool
    width:        s32
    height:       s32
}

impl Mpeg4Stream
{
    // Configures the decoder from a container's decoder configuration and installs the samples.
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
        .decoder.reset()
    }

    mtd releasePending()
    {
    }

    // Decodes forward until the picture of the current rank is reconstructed.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        if .nextRank >= .sampleAtRank.count do
            fail InvalidFormatError{"MPEG-4 stream has no picture at the requested position"}

        let wanted = cast(u64) .sampleAtRank[.nextRank]

        // A picture that is not a clean decode point needs everything back to the last one.
        if !.started or wanted < .nextDecode
        {
            .decoder.reset()
            .nextDecode = cast(u64) .sampleAtRank[.syncRankAt(.nextRank)]
            .started    = true
        }

        while .nextDecode <= wanted
        {
            let entry = .frames[.nextDecode]
            .payload.resize(entry.size)
            try source.seek(entry.offset)
            try source.readExact(.payload.toSlice())
            discard try .decoder.decodeSample(.payload.toSlice(), entry.presentationTime)
            .nextDecode += 1
        }

        .decoder.reference().writePlanar(target)
        .nextRank += 1
    }

    // Decodes the picture of the current rank and converts it to packed colour.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        var planes: PlanarFrame
        try .decodeNextPlanes(source, &planes)
        planes.view().convertToRgb(target)
    }
}
