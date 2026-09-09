#global internal
#global namespace Pipeline

using Core

// One producer and one consumer exchange complete BGRA frames. Publication and acknowledgement
// are atomic; neither side touches the other's frame until ownership has changed.
struct FrameHeader
{
    published: u32
    consumed:  u32
    renderUs:  u32
    click:     u32
    clickX:    u32
    clickY:    u32
    clicked:   u32
    reserved:  [9] u32
}

#[Swag.NoCopy]
struct FrameChannel
{
    region: File.MappedRegion
}

impl FrameChannel
{
    const Width     = 640's32
    const Height    = 400's32
    const ByteCount = cast(u64) (Width * Height * 4)

    mtd open(path: string, create = false) fail
    {
        .region.close()
        if create do
            discard try File.writeAllBytes(path, {})
        var file = try File.MappedFile.open(path, .ReadWrite)
        if create do
            try file.resize(#sizeof(FrameHeader) + ByteCount)
        .region = try file.map(0, #sizeof(FrameHeader) + ByteCount)
        if create do
            Memory.set(.region.writableBytes().buffer, 0, .region.length)
    }

    mtd header()->*FrameHeader => cast(*FrameHeader) .region.writableBytes().buffer
    mtd pixels()->[*] u8       => .region.writableBytes().buffer + #sizeof(FrameHeader)
    mtd close() { .region.close() }
}
