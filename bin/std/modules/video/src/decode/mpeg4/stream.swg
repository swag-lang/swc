//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, and both the H.263 and MPEG quantisers.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns an indexed track: seeking, decoding on demand, and handing pictures over.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors, Pixel

// Drives an indexed MPEG-4 Part 2 track independently of its container.
//
// Without bidirectional planes the display order is the decoding order, so a rank is a sample.
#[Swag.NoCopy]
struct Mpeg4Stream
{
    decoder:  Decoder
    config:   Array'u8
    frames:   Array'SampleEntry
    payload:  Array'u8
    nextRank: u64
    width:    s32
    height:   s32
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
        .frames = #move frames
        .nextRank = 0
        .decoder.reset()
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: Array'SampleEntry) fail
    {
        .frames   = #move frames
        .nextRank = 0
        .decoder.reset()
    }

    // Extends the window with samples the reader has since indexed.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        .frames.add(frames)
    }

    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        if rank >= .frames.count do
            return 0
        return .frames[rank].presentationTime
    }

    // Returns the first rank at or after `rank` whose sample starts a clean decode.
    mtd const syncRankAt(rank: u64)->u64
    {
        var scan = rank
        while scan < .frames.count
        {
            if .frames[scan].isSync do
                return scan
            if !scan do
                break
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
        .decoder.reset()
    }

    mtd releasePending()
    {
    }

    // Decodes forward until the picture of the current rank is reconstructed.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        if .nextRank >= .frames.count do
            fail InvalidFormatError{"MPEG-4 stream has no picture at the requested position"}

        // A predicted picture needs everything back to its last clean decode point.
        var at = .nextRank
        if !.decoder.hasPast do
            at = .syncRankAt(.nextRank)

        while at <= .nextRank
        {
            let entry = .frames[at]
            .payload.resize(entry.size)
            try source.seek(entry.offset)
            try source.readExact(.payload.toSlice())
            discard try .decoder.decodeSample(.payload.toSlice())
            at += 1
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
