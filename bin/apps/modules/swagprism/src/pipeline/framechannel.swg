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

// The file both processes map to exchange frames: a [[FrameHeader]] followed by one BGRA frame,
// and the named event the producer waits on until the consumer has taken the frame.
#[Swag.NoCopy]
struct FrameChannel
{
    region:        File.MappedRegion
    consumedEvent: Sync.Event
}

impl FrameChannel
{
    const Width     = 640's32
    const Height    = 400's32
    const ByteCount = cast(u64, (Width * Height * 4))

    #[Swag.Propagate]
    mtd open(path: string, create = false) fail
    {
        .close()
        if create do
            discard File.writeAllBytes(path, {})
        var file = File.MappedFile.open(path, .ReadWrite)
        if create do
            file.resize(#sizeof(FrameHeader) + ByteCount)
        .region = file.map(0, #sizeof(FrameHeader) + ByteCount)
        if create do
            Memory.set(.region.writableBytes().buffer, 0, .region.length)
        let name = Format.toString("SwagPrism.%", Path.fileName(Path.directoryName(path)))
        .consumedEvent.initNamed(name)
    }

    mtd header()->*FrameHeader => cast(*FrameHeader, .region.writableBytes().buffer)
    mtd pixels()->[*] u8       => .region.writableBytes().buffer + #sizeof(FrameHeader)

    // Tells the producer that `frame` was copied, so it may write the next one.
    mtd acknowledge(frame: u32)
    {
        Atomic.exchange(&.header().consumed, frame)
        .consumedEvent.signal()
    }

    // A named event wakes the child immediately, without Sleep's system-timer granularity.
    // The atomic counters remain the ownership predicate, including signals sent before a wait.
    mtd waitConsumed()
    {
        while Atomic.get(&.header().published) != Atomic.get(&.header().consumed) do
            .consumedEvent.wait()
    }

    mtd close()
    {
        .consumedEvent.release()
        .region.close()
    }
}
