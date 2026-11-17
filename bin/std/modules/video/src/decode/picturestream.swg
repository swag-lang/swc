//! Format: Format-neutral coded picture track.
//! Supported: Opening, extending, replacing, seeking, and decoding indexed H.264, H.265, MPEG-4 Part 2, and RealVideo 4 tracks through one surface.
//! Not supported: This file does not decode or encode a concrete picture format.
//! Role: This file owns which coded picture format a container opened, so no reader has to ask.
//
#global internal

using Core, Core.Errors, Pixel

// Which coded picture format a container named.
const PictureAvc       = 0'u32
const PictureHevc      = 1'u32
const PictureMpeg4     = 2'u32
const PictureRealVideo = 3'u32

// Converts a codec pixel aspect ratio to display dimensions, returning zero dimensions for
// square pixels so callers can preserve the StreamInfo convention.
func pictureDisplaySize(width, height: s32, aspectWidth, aspectHeight: u32)->{ width, height: s32 }
{
    if width <= 0 or height <= 0 or not aspectWidth or not aspectHeight do
        return {width: 0, height: 0}

    let codedWidth  = cast(u64, width) * aspectWidth
    let codedHeight = cast(u64, height) * aspectHeight
    if codedWidth == codedHeight do
        return {width: 0, height: 0}

    if codedWidth > codedHeight
    {
        let displayWidth = (cast(u64, width) * aspectWidth + aspectHeight / 2) / aspectHeight
        if displayWidth > Swag.S32.Max do
            return {width: 0, height: 0}
        return {width: cast(s32, displayWidth), height: height}
    }

    let displayHeight = (cast(u64, height) * aspectHeight + aspectWidth / 2) / aspectWidth
    if displayHeight > Swag.S32.Max do
        return {width: 0, height: 0}
    return {width: width, height: cast(s32, displayHeight)}
}

// The coded picture track of one container, whichever picture codec named it.
//
// Each codec consumes indexed access units in decoding order and returns pictures in display
// order. Container readers use this dispatch for every operation on that shared contract.
#[Swag.NoCopy]
struct PictureStream
{
    avc:       H264.AvcStream
    hevc:      Hevc.HevcStream
    mpeg4:     Mpeg4.Mpeg4Stream
    realvideo: RealVideo.Stream
    kind:      u32
    sampleAspectWidth:  u32 = 1
    sampleAspectHeight: u32 = 1
}

impl PictureStream
{
    // Applies a pixel aspect ratio without changing the coded frame dimensions. A zero ratio
    // means the caller has no container override and the codec ratio is used.
    mtd const displaySize(width, height: s32, aspectWidth = 0, aspectHeight = 0)->{ width, height: s32 }
    {
        let ratioWidth  = aspectWidth ? aspectWidth : .sampleAspectWidth
        let ratioHeight = aspectHeight ? aspectHeight : .sampleAspectHeight
        return pictureDisplaySize(width, height, ratioWidth, ratioHeight)
    }

    // Configures the decoder from the container's decoder configuration record and installs the
    // access units of the track. `kind` selects the codec and its configuration format.
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
            .sampleAspectWidth  = .hevc.sampleAspectWidth
            .sampleAspectHeight = .hevc.sampleAspectHeight

        case PictureRealVideo:
            .realvideo.prefix.clear()
            .realvideo.prefix.add(prefix)
            try .realvideo.open(config, #move owned)

        case PictureMpeg4:
            .mpeg4.prefix.clear()
            .mpeg4.prefix.add(prefix)
            try .mpeg4.open(config, #move owned)

        default:
            .avc.prefix.clear()
            .avc.prefix.add(prefix)
            try .avc.open(config, #move owned)
            .sampleAspectWidth  = .avc.sampleAspectWidth
            .sampleAspectHeight = .avc.sampleAspectHeight
        }
    }

    // Extends the container window with access units the reader has since indexed.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        switch .kind
        {
        case PictureHevc:      try .hevc.appendFrames(frames)
        case PictureMpeg4:     try .mpeg4.appendFrames(frames)
        case PictureRealVideo: try .realvideo.appendFrames(frames)
        default: try .avc.appendFrames(frames)
        }
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: const [..] SampleEntry) fail
    {
        var owned: Array'SampleEntry
        owned.add(frames)
        switch .kind
        {
        case PictureHevc:      try .hevc.replaceFrames(#move owned)
        case PictureMpeg4:     try .mpeg4.replaceFrames(#move owned)
        case PictureRealVideo: try .realvideo.replaceFrames(#move owned)
        default: try .avc.replaceFrames(#move owned)
        }
    }

    // Frame width, in pixels, after the stream's own cropping.
    mtd const width()->s32
    {
        if .kind == PictureHevc do
            return .hevc.width
        if .kind == PictureRealVideo do
            return .realvideo.width
        if .kind == PictureMpeg4 do
            return .mpeg4.width
        return .avc.width
    }

    // Frame height, in pixels, after the stream's own cropping.
    mtd const height()->s32
    {
        if .kind == PictureHevc do
            return .hevc.height
        if .kind == PictureRealVideo do
            return .realvideo.height
        if .kind == PictureMpeg4 do
            return .mpeg4.height
        return .avc.height
    }

    // Number of access units the stream currently holds.
    mtd const frameCount()->u64
    {
        if .kind == PictureHevc do
            return .hevc.frames.count
        if .kind == PictureRealVideo do
            return .realvideo.sampleAtRank.count
        if .kind == PictureMpeg4 do
            return .mpeg4.sampleAtRank.count
        return .avc.frames.count
    }

    // Returns the container presentation timestamp of one display-order picture.
    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        if .kind == PictureHevc do
            return .hevc.presentationTimeAtRank(rank)
        if .kind == PictureRealVideo do
            return .realvideo.presentationTimeAtRank(rank)
        if .kind == PictureMpeg4 do
            return .mpeg4.presentationTimeAtRank(rank)
        return .avc.presentationTimeAtRank(rank)
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    mtd const syncRankAt(rank: u64)->u64
    {
        if .kind == PictureHevc do
            return .hevc.syncRankAt(rank)
        if .kind == PictureRealVideo do
            return .realvideo.syncRankAt(rank)
        if .kind == PictureMpeg4 do
            return .mpeg4.syncRankAt(rank)
        return .avc.syncRankAt(rank)
    }

    // Positions the stream so the next decoded picture has display rank `rank`.
    mtd seekTo(rank: u64)
    {
        if .kind == PictureHevc do
            .hevc.seekTo(rank)
        elif .kind == PictureRealVideo do
            .realvideo.seekTo(rank)
        elif .kind == PictureMpeg4 do
            .mpeg4.seekTo(rank)
        else do
            .avc.seekTo(rank)
    }

    // Decodes the picture with the current display rank and converts it to packed colour.
    mtd decodeNext(source: *ByteSource, target: *Image) fail
    {
        switch .kind
        {
        case PictureHevc:      try .hevc.decodeNext(source, target)
        case PictureMpeg4:     try .mpeg4.decodeNext(source, target)
        case PictureRealVideo: try .realvideo.decodeNext(source, target)
        default: try .avc.decodeNext(source, target)
        }
    }

    // Decodes the picture with the current display rank and hands over its planes unconverted.
    mtd decodeNextPlanes(source: *ByteSource, target: *PlanarFrame) fail
    {
        switch .kind
        {
        case PictureHevc:      try .hevc.decodeNextPlanes(source, target)
        case PictureMpeg4:     try .mpeg4.decodeNextPlanes(source, target)
        case PictureRealVideo: try .realvideo.decodeNextPlanes(source, target)
        default: try .avc.decodeNextPlanes(source, target)
        }
    }

    // Releases every picture waiting for its display turn.
    mtd releasePending()
    {
        if .kind == PictureHevc do
            .hevc.releasePending()
        elif .kind == PictureRealVideo do
            .realvideo.releasePending()
        elif .kind == PictureMpeg4 do
            .mpeg4.releasePending()
        else do
            .avc.releasePending()
    }
}
