//! Format: Format-neutral coded picture track.
//! Supported: Opening, extending, replacing, seeking, and decoding an indexed H.264 or H.265 track through one surface.
//! Not supported: This file does not decode or encode a concrete picture format.
//! Role: This file owns which of the two coded picture formats a container opened, so no reader has to ask.
//
#global internal

using Core, Core.Errors, Pixel

// Which coded picture format a container named.
const PictureAvc   = 0'u32
const PictureHevc  = 1'u32
const PictureMpeg4 = 2'u32

// The coded picture track of one container, whichever picture codec named it.
//
// H.264 and H.265 present a container with the same thing: a table of length-prefixed access
// units in decoding order, each with the time it is shown, and a decoder that reorders them. A
// container therefore has no reason to know which of the two it opened, and every reader that
// asked the question separately eventually forgot to ask it somewhere. This holds the answer once.
#[Swag.NoCopy]
struct PictureStream
{
    avc:   H264.AvcStream
    hevc:  Hevc.HevcStream
    mpeg4: Mpeg4.Mpeg4Stream
    kind:  u32
}

impl PictureStream
{
    // Configures the decoder from the container's decoder configuration record and installs the
    // access units of the track. `hevc` selects H.265, and with it an `hvcC` record.
    // `prefix` is what the container took off the front of every stored frame, if it did.
    mtd open(kind: u32, config: const [..] u8, frames: const [..] SampleEntry, prefix: const [..] u8) fail
    {
        var owned: Array'SampleEntry
        owned.add(frames)
        .kind = kind
        switch kind
        {
        case PictureHevc:
            .hevc.prefix.clear()
            .hevc.prefix.add(prefix)
            try .hevc.open(config, #move owned)

        case PictureMpeg4:
            .mpeg4.prefix.clear()
            .mpeg4.prefix.add(prefix)
            try .mpeg4.open(config, #move owned)

        default:
            .avc.prefix.clear()
            .avc.prefix.add(prefix)
            try .avc.open(config, #move owned)
        }
    }

    // Extends the container window with access units the reader has since indexed.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        switch .kind
        {
        case PictureHevc:  try .hevc.appendFrames(frames)
        case PictureMpeg4: try .mpeg4.appendFrames(frames)
        default:           try .avc.appendFrames(frames)
        }
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: const [..] SampleEntry) fail
    {
        var owned: Array'SampleEntry
        owned.add(frames)
        switch .kind
        {
        case PictureHevc:  try .hevc.replaceFrames(#move owned)
        case PictureMpeg4: try .mpeg4.replaceFrames(#move owned)
        default:           try .avc.replaceFrames(#move owned)
        }
    }

    // Frame width, in pixels, after the stream's own cropping.
    mtd const width()->s32 => .kind == PictureHevc ? .hevc.width : (.kind == PictureMpeg4 ? .mpeg4.width : .avc.width)

    // Frame height, in pixels, after the stream's own cropping.
    mtd const height()->s32 => .kind == PictureHevc ? .hevc.height : (.kind == PictureMpeg4 ? .mpeg4.height : .avc.height)

    // Number of access units the stream currently holds.
    mtd const frameCount()->u64 => .kind == PictureHevc ? .hevc.frames.count : (.kind == PictureMpeg4 ? .mpeg4.sampleAtRank.count : .avc.frames.count)

    // Returns the container presentation timestamp of one display-order picture.
    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        if .kind == PictureHevc do
            return .hevc.presentationTimeAtRank(rank)
        if .kind == PictureMpeg4 do
            return .mpeg4.presentationTimeAtRank(rank)
        return .avc.presentationTimeAtRank(rank)
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    mtd const syncRankAt(rank: u64)->u64
    {
        if .kind == PictureHevc do
            return .hevc.syncRankAt(rank)
        if .kind == PictureMpeg4 do
            return .mpeg4.syncRankAt(rank)
        return .avc.syncRankAt(rank)
    }

    // Positions the stream so the next decoded picture has display rank `rank`.
    mtd seekTo(rank: u64)
    {
        if .kind == PictureHevc do
            .hevc.seekTo(rank)
        elif .kind == PictureMpeg4 do
            .mpeg4.seekTo(rank)
        else do
            .avc.seekTo(rank)
    }

    // Decodes the picture with the current display rank and converts it to packed colour.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        switch .kind
        {
        case PictureHevc:  try .hevc.decodeNext(source, target)
        case PictureMpeg4: try .mpeg4.decodeNext(source, target)
        default:           try .avc.decodeNext(source, target)
        }
    }

    // Decodes the picture with the current display rank and hands over its planes unconverted.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        switch .kind
        {
        case PictureHevc:  try .hevc.decodeNextPlanes(source, target)
        case PictureMpeg4: try .mpeg4.decodeNextPlanes(source, target)
        default:           try .avc.decodeNextPlanes(source, target)
        }
    }

    // Releases every picture waiting for its display turn.
    mtd releasePending()
    {
        if .kind == PictureHevc do
            .hevc.releasePending()
        elif .kind == PictureMpeg4 do
            .mpeg4.releasePending()
        else do
            .avc.releasePending()
    }
}
