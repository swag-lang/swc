#global namespace Frames

// Reads the frames of a frame file by index or by time.
//
// Opening reads the index from the trailer, or rebuilds it by scanning the records of a file
// whose recording was cut short. The reader then keeps one decoded picture: reading the next frame
// applies one record to it, and any other frame replays at most the records since the key record
// before it.
#[Swag.NoCopy]
struct Reader
{
    source:       ByteSource
    fileName:     String
    width:        s32
    height:       s32
    pixelFormat:  PixelFormat
    index:        Array'Entry // Recovered files without a trailer are scanned into this index.
    mappedIndex:  File.MappedRegion // Complete files keep their index in the file, not the heap.
    mappedCount:  u64
    endTime:      u64       // Time the last frame stops being shown, in microseconds.
    isRecovered:  bool      // The trailer was missing and the index was rebuilt by a scan.
    picture:      Image     // The frame at `pictureIndex`, once one was read.
    pictureIndex: u64 = Swag.U64.Max
    inflate:      Compress.Inflate
    payload:      Array'u8
    rows:         Array'u8
}

impl Reader
{
    // Opens the frame file `fileName` and reads its index.
    func open(fileName: string)->Reader fail
    {
        var result: #returntype
        result.fileName = fileName
        result.source = try ByteSource.openFile(fileName)
        if result.source.size() < HeaderSize do
            fail Errors.InvalidFormatError{}

        if try result.source.readLittleEndian'u64() != Magic do
            fail Errors.InvalidFormatError{}
        if try result.source.readLittleEndian'u32() != Version do
            fail Errors.InvalidFormatError{}

        result.width       = cast(s32, try result.source.readLittleEndian'u32())
        result.height      = cast(s32, try result.source.readLittleEndian'u32())
        result.pixelFormat = try framePixelFormat(try result.source.readLittleEndian'u32())
        if result.width <= 0 or result.height <= 0 do
            fail Errors.InvalidFormatError{}

        if not try result.readTrailer() do
            try result.scanRecords()
        // An interrupted writer may have left its temporary spool. The media itself recovers
        // from complete records, and never needs that spool after it has been opened.
        var stale = String.from(fileName)
        stale += ".index.tmp"
        if File.exists(stale) do
            discard catch File.delete(stale)
        if result.frameCount() == 0 do
            fail Errors.InvalidFormatError{}

        result.picture = Image.create(result.width, result.height, result.pixelFormat)
        return result
    }

    // Returns the number of frames in the file.
    mtd const frameCount()->u64 => .mappedIndex.isOpen() ? .mappedCount : .index.count

    // Reads one trailer entry on demand. Recovered files use the scanned index.
    private mtd const entryAt(frame: u64)->Entry
    {
        if not .mappedIndex.isOpen() do
            return .index[frame]
        Swag.assert(frame < .mappedCount)
        let bytes = .mappedIndex.bytes()
        let from = bytes.buffer + frame * IndexEntrySize
        var result: Entry
        var kind: u32
        Memory.copy(&result.offset, from, 8)
        Memory.copy(&result.time, from + 8, 8)
        Memory.copy(&kind, from + 16, 4)
        result.offset = Math.littleEndianToNative(result.offset)
        result.time   = Math.littleEndianToNative(result.time)
        result.kind   = Math.littleEndianToNative(kind) == cast(u32, FrameKind.Key) ? .Key : .Delta
        return result
    }

    // Returns the time frame `frame` is shown, in microseconds from the start.
    mtd const timeOf(frame: u64)->u64 => .entryAt(frame).time

    // Returns the frame shown at `time` microseconds from the start.
    mtd const frameAt(time: u64)->u64
    {
        // The last frame whose time is not after `time`.
        var low  = 0'u64
        var high = .frameCount()
        while high - low > 1
        {
            let middle = (low + high) / 2
            if .timeOf(middle) <= time do
                low = middle
            else do
                high = middle
        }

        return low
    }

    // Returns the picture of frame `frame`. The result is borrowed until the next read.
    mtd read(frame: u64)->const *Image fail
    {
        Swag.assert(frame < .frameCount())
        if frame == .pictureIndex do
            return &.picture

        // Replay from the key record at or before the frame, unless the frame follows the
        // picture already decoded after that key.
        var key = frame
        while key > 0 and .entryAt(key).kind != .Key do
            key -= 1
        if .entryAt(key).kind != .Key do
            fail Errors.InvalidFormatError{}

        let start = .pictureIndex != Swag.U64.Max and .pictureIndex >= key and .pictureIndex < frame ? .pictureIndex + 1 : key
        for record in start to frame do
            try .apply(record)

        .pictureIndex = frame
        return &.picture
    }

    // Applies record `record` to the decoded picture.
    private mtd apply(record: u64) fail
    {
        try .source.seek(.entryAt(record).offset)
        if try .source.readLittleEndian'u32() != RecordTag do
            fail Errors.InvalidFormatError{}

        let kind = try frameKind(try .source.readLittleEndian'u32())
        if kind != .entryAt(record).kind do
            fail Errors.InvalidFormatError{}
        discard try .source.readLittleEndian'u64()

        var area: Area
        area.x = cast(s32, try .source.readLittleEndian'u32())
        area.y = cast(s32, try .source.readLittleEndian'u32())
        area.w = cast(s32, try .source.readLittleEndian'u32())
        area.h = cast(s32, try .source.readLittleEndian'u32())
        let payloadSize = try .source.readLittleEndian'u32()
        discard try .source.readLittleEndian'u32()
        if area.isEmpty() do
            return

        if area.x < 0 or area.y < 0 or area.x + area.w > .width or area.y + area.h > .height do
            fail Errors.InvalidFormatError{}

        .payload.resize(payloadSize)
        try .source.readExact(.payload.toSlice())

        let expected = cast(u64, area.w * area.h * .picture.bytesPerPixel)
        .rows.clear()
        try .inflate.decompress(&.rows, .payload.toSlice(), maxOutputSize: expected)
        if .rows.count != expected do
            fail Errors.InvalidFormatError{}

        writeArea(&.picture, area, .rows.toSlice())
    }

    // Reads the index and the end time from the trailer; false when the file has none.
    private mtd readTrailer()->bool fail
    {
        let size = .source.size()
        if size < HeaderSize + FooterSize do
            return false

        try .source.seek(size - FooterSize)
        let indexOffset = try .source.readLittleEndian'u64()
        let endTime     = try .source.readLittleEndian'u64()
        if try .source.readLittleEndian'u64() != EndMagic do
            return false
        if indexOffset < HeaderSize or indexOffset >= size - FooterSize do
            return false

        try .source.seek(indexOffset)
        if try .source.readLittleEndian'u32() != IndexTag do
            return false
        discard try .source.readLittleEndian'u32()
        let count = try .source.readLittleEndian'u64()
        if count * IndexEntrySize != size - FooterSize - indexOffset - 16 do
            return false

        var mapped = try File.MappedFile.open(.fileName)
        defer mapped.close()
        .mappedIndex = try mapped.map(indexOffset + 16, count * IndexEntrySize)
        .mappedCount = count

        .endTime = endTime
        return true
    }

    // Rebuilds the index from the records that were completely written, after a recording cut
    // short. The last frame is then shown for as long as the one before it.
    private mtd scanRecords() fail
    {
        .isRecovered = true

        let size   = .source.size()
        var offset = HeaderSize
        while offset + RecordSize <= size
        {
            try .source.seek(offset)
            if try .source.readLittleEndian'u32() != RecordTag do
                break

            var entry: Entry
            entry.offset = offset
            entry.kind   = try frameKind(try .source.readLittleEndian'u32())
            entry.time   = try .source.readLittleEndian'u64()
            try .source.skip(16)
            let payloadSize = try .source.readLittleEndian'u32()

            let next = offset + RecordSize + payloadSize
            if next > size do
                break
            if not .index.isEmpty() and entry.time < .index.back().time do
                break
            if .index.isEmpty() and entry.kind != .Key do
                break

            .index.add(entry)
            offset = next
        }

        if .index.isEmpty() do
            return

        let last = .index.back().time
        .endTime = .index.count > 1 ? last + (last - .index[.index.count - 2].time) : last + KeyInterval
    }
}
