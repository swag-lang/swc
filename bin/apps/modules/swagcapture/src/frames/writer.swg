#global namespace Frames

// Appends the frames of a recording to a frame file.
//
// The writer keeps one copy of the last frame, to find what the next one changed, and one index
// entry per frame for the trailer; nothing else grows with the length of the recording. Frames
// must be added in time order and all share the geometry and pixel format given at creation.
// [[Frames.Writer.close]] writes the index and decides whether the file is complete, so its
// failure must be handled.
#[Swag.NoCopy]
struct Writer
{
    sink:        ByteSink
    width:       s32
    height:      s32
    pixelFormat: PixelFormat
    previous:    Image           // Last frame added, compared with the next one.
    index:       Array'Entry     // One entry per record, written as the trailer.
    lastKey:     u64             // Time of the last key record.
    deflate:     Compress.Deflate
    rows:        Array'u8     // Pixels of the area being written, top row first.
    payload:     Array'u8     // Compressed pixels of the area being written.
    isClosed:    bool
}

impl Writer
{
    // Creates `fileName` and writes the header of a frame file for frames of this geometry.
    func create(fileName: string, width, height: s32, pixelFormat: PixelFormat)->Writer fail
    {
        Swag.assert(width > 0 and height > 0)
        Swag.assert(pixelFormat == .BGRA8 or pixelFormat == .RGBA8)

        var result: #returntype
        result.sink        = try ByteSink.createFile(fileName)
        result.width       = width
        result.height      = height
        result.pixelFormat = pixelFormat

        try result.sink.writeLittleEndian(Magic)
        try result.sink.writeLittleEndian(Version)
        try result.sink.writeLittleEndian(cast(u32, width))
        try result.sink.writeLittleEndian(cast(u32, height))
        try result.sink.writeLittleEndian(cast(u32, pixelFormat))
        try result.sink.writeLittleEndian(0'u64)
        return result
    }

    // Returns the number of frames added so far.
    mtd const frameCount()->u64 => .index.count

    // Appends `frame`, shown from `time` microseconds after the start of the recording.
    //
    // A key record stores the whole picture about once a second; the frames between store only
    // the rectangle that changed since the previous one, which is empty when nothing moved.
    mtd add(frame: Image, time: u64) fail
    {
        Swag.assert(not .isClosed)
        Swag.assert(frame.width == .width and frame.height == .height and frame.pixelFormat == .pixelFormat)
        Swag.assert(.index.isEmpty() or time >= .index.back().time)

        let isKey      = .index.isEmpty() or time - .lastKey >= KeyInterval
        let area: Area = isKey ? {0, 0, .width, .height} : changedArea(.previous, frame)

        var entry = Entry{offset: .sink.position(), time: time, kind: isKey ? .Key : .Delta}
        .payload.clear()
        if not area.isEmpty()
        {
            readArea(frame, area, &.rows)
            .deflate.init(.BestSpeed)
            try .deflate.compress(&.payload, .rows.toSlice())
        }

        try .sink.writeLittleEndian(RecordTag)
        try .sink.writeLittleEndian(cast(u32, entry.kind))
        try .sink.writeLittleEndian(time)
        try .sink.writeLittleEndian(cast(u32, area.x))
        try .sink.writeLittleEndian(cast(u32, area.y))
        try .sink.writeLittleEndian(cast(u32, area.w))
        try .sink.writeLittleEndian(cast(u32, area.h))
        try .sink.writeLittleEndian(cast(u32, .payload.count))
        try .sink.writeLittleEndian(0'u32)
        try .sink.write(.payload.toSlice())

        // The previous frame only needs the rows that changed, which is all of them for a key.
        if not .previous.isValid() do
            .previous = frame
        elif not area.isEmpty() do
            writeArea(&.previous, area, .rows.toSlice())

        if isKey do
            .lastKey = time
        .index.add(entry)
    }

    // Writes the index and the footer, the last frame being shown until `endTime`, and closes the
    // file.
    mtd close(endTime: u64) fail
    {
        if .isClosed do
            return
        .isClosed = true

        let indexOffset = .sink.position()
        try .sink.writeLittleEndian(IndexTag)
        try .sink.writeLittleEndian(0'u32)
        try .sink.writeLittleEndian(cast(u64, .index.count))
        for entry in .index
        {
            try .sink.writeLittleEndian(entry.offset)
            try .sink.writeLittleEndian(entry.time)
            try .sink.writeLittleEndian(cast(u32, entry.kind))
            try .sink.writeLittleEndian(0'u32)
        }

        try .sink.writeLittleEndian(indexOffset)
        try .sink.writeLittleEndian(endTime)
        try .sink.writeLittleEndian(EndMagic)
        try .sink.close()
    }

    // Returns the smallest rectangle holding every pixel that differs between two frames of the
    // same geometry; empty when they are identical.
    func changedArea(before, after: Image)->Area
    {
        let rowBytes = cast(u64, after.width * after.bytesPerPixel)
        let first    = before.pixels.storage()
        let second   = after.pixels.storage()

        func differs(a, b: const [*] u8, size: u64)->bool => Memory.compare(a, b, size) != 0

        // Rows that changed, in picture coordinates.
        var top    = -1
        var bottom = -1
        for y in after.height
        {
            let offset = cast(u64, (after.height - 1 - y) * after.rowStride)
            if differs(first + offset, second + offset, rowBytes)
            {
                if top < 0 do
                    top = y
                bottom = y
            }
        }

        if top < 0 do
            return {}

        // Columns that changed, within those rows.
        let pixelBytes = cast(u64, after.bytesPerPixel)
        var left       = after.width
        var right      = -1
        for y in top to bottom
        {
            let offset = cast(u64, (after.height - 1 - y) * after.rowStride)
            let a      = first + offset
            let b      = second + offset
            for x in left where differs(a + cast(u64, x) * pixelBytes, b + cast(u64, x) * pixelBytes, pixelBytes)
            {
                left = x
                break
            }

            var x = after.width - 1
            while x > right
            {
                if differs(a + cast(u64, x) * pixelBytes, b + cast(u64, x) * pixelBytes, pixelBytes)
                {
                    right = x
                    break
                }

                x -= 1
            }
        }

        return {left, top, right - left + 1, bottom - top + 1}
    }
}
