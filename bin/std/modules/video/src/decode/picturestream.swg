#global internal

using Core, Core.Errors, Pixel

// The coded picture track of one container, whichever picture codec named it.
//
// H.264 and H.265 present a container with the same thing: a table of length-prefixed access
// units in decoding order, each with the time it is shown, and a decoder that reorders them. A
// container therefore has no reason to know which of the two it opened, and every reader that
// asked the question separately eventually forgot to ask it somewhere. This holds the answer once.
#[Swag.NoCopy]
struct PictureStream
{
    avc:    H264.AvcStream
    hevc:   Hevc.HevcStream
    isHevc: bool
}

impl PictureStream
{
    // Configures the decoder from the container's decoder configuration record and installs the
    // access units of the track. `hevc` selects H.265, and with it an `hvcC` record.
    mtd open(hevc: bool, config: const [..] u8, frames: const [..] SampleEntry) fail
    {
        var owned: Array'SampleEntry
        owned.add(frames)
        .isHevc = hevc
        if hevc
        {
            try .hevc.open(config, #move owned)
        }
        else
        {
            try .avc.open(config, #move owned)
        }
    }

    // Extends the container window with access units the reader has since indexed.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        if .isHevc
        {
            try .hevc.appendFrames(frames)
        }
        else
        {
            try .avc.appendFrames(frames)
        }
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: const [..] SampleEntry) fail
    {
        var owned: Array'SampleEntry
        owned.add(frames)
        if .isHevc
        {
            try .hevc.replaceFrames(#move owned)
        }
        else
        {
            try .avc.replaceFrames(#move owned)
        }
    }

    // Frame width, in pixels, after the stream's own cropping.
    mtd const width()->s32 => .isHevc ? .hevc.width : .avc.width

    // Frame height, in pixels, after the stream's own cropping.
    mtd const height()->s32 => .isHevc ? .hevc.height : .avc.height

    // Number of access units the stream currently holds.
    mtd const frameCount()->u64 => .isHevc ? .hevc.frames.count : .avc.frames.count

    // Returns the container presentation timestamp of one display-order picture.
    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        if .isHevc do
            return .hevc.presentationTimeAtRank(rank)
        return .avc.presentationTimeAtRank(rank)
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    mtd const syncRankAt(rank: u64)->u64
    {
        if .isHevc do
            return .hevc.syncRankAt(rank)
        return .avc.syncRankAt(rank)
    }

    // Positions the stream so the next decoded picture has display rank `rank`.
    mtd seekTo(rank: u64)
    {
        if .isHevc do
            .hevc.seekTo(rank)
        else do
            .avc.seekTo(rank)
    }

    // Decodes the picture with the current display rank and converts it to packed colour.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        if .isHevc
        {
            try .hevc.decodeNext(source, target)
        }
        else
        {
            try .avc.decodeNext(source, target)
        }
    }

    // Decodes the picture with the current display rank and hands over its planes unconverted.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        if .isHevc
        {
            try .hevc.decodeNextPlanes(source, target)
        }
        else
        {
            try .avc.decodeNextPlanes(source, target)
        }
    }

    // Releases every picture waiting for its display turn.
    mtd releasePending()
    {
        if .isHevc do
            .hevc.releasePending()
        else do
            .avc.releasePending()
    }
}
