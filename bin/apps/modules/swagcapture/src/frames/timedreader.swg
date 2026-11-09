using Core, Pixel, Video

// Presents GIF frame files and MP4 pictures through the same indexed timeline contract.
#[Swag.NoCopy]
struct TimedReader
{
    frames:  Frames.Reader
    video:   Reader
    picture: Image
    media:   CaptureMedia
    width:   s32
    height:  s32
    endTime: u64
}

impl TimedReader
{
    func open(path: string, media: CaptureMedia)->TimedReader fail
    {
        var result: #returntype
        result.media = media
        if media == .Video
        {
            result.video = try Reader.open(path, pictureOnly: true)
            result.width = result.video.width()
            result.height = result.video.height()
            result.endTime = cast(u64, Math.round(result.video.durationInSeconds() * 1_000_000))
        }
        else
        {
            result.frames = try Frames.Reader.open(path)
            result.width = result.frames.width
            result.height = result.frames.height
            result.endTime = result.frames.endTime
        }
        return result
    }

    mtd const frameCount()->u64 => .media == .Video ? .video.frameCount() : .frames.frameCount()

    mtd const timeOf(frame: u64)->u64 => .media == .Video ?
        cast(u64, Math.round(.video.frameTimestamp(frame) * 1_000_000)) : .frames.timeOf(frame)

    mtd const frameAt(time: u64)->u64
    {
        if .media != .Video do
            return .frames.frameAt(time)
        // The editor stores microseconds; include the rounded microsecond when converting back
        // to the source timescale so a frame's displayed time selects that frame again.
        return Math.min(.video.frameAtTime((cast(f64, time) + 0.5) / 1_000_000),
                        .video.frameCount() - 1)
    }

    mtd read(frame: u64)->const *Image fail
    {
        if .media != .Video do
            return try .frames.read(frame)
        try .video.decodeFrameInto(&.picture, frame)
        return &.picture
    }
}
