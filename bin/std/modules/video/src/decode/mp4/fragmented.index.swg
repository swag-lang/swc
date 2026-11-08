//! Format: ISO Base Media File Format (MP4) movie fragment random-access index.
//! Supported: Version 0 and 1 `tfra` entries at the end of a completed file.
//! Not supported: Indexes without a final `mfro`, and files still being recorded.
//! Role: This file finds video fragment offsets without scanning the movie's media data.
//
#global namespace Mp4
#global export

using Core, Core.Errors

private const IndexTrackAccessId = fourCc('t'u32, 'f'u32, 'r'u32, 'a'u32)
private const IndexOffsetId      = fourCc('m'u32, 'f'u32, 'r'u32, 'o'u32)

// One sync sample located by a fragmented MP4 random-access index.
//
// `decodeTime` uses the indexed track's timescale. `moofOffset` is an absolute file offset;
// the three one-based numbers select its track fragment, run, and sample.
struct FragmentedSeekPoint
{
    public decodeTime:          u64     // Decode-time ticks in the indexed track.
    public moofOffset:          u64     // Absolute byte offset of the movie fragment.
    public trackFragmentNumber: u32     // One-based track fragment number inside `moof`.
    public trackRunNumber:      u32     // One-based track run number inside that track fragment.
    public sampleNumber:        u32     // One-based sample number inside that track run.
}

// Reads the final `mfra` index of one fragmented MP4 track with bounded memory.
//
// Opening reads the last box and validates its entries, without scanning media fragments. Lookup
// uses binary search and reads entries directly from the file. The file must stay unchanged while
// this value is open; call `close` to release it early.
#[Swag.NoCopy]
struct FragmentedIndex
{
    private
    {
        source:             ByteSource
        tableOffset:        u64
        randomAccessOffset: u64
        entrySize:          u32
        count:              u32
        trackFragmentBytes: u8
        trackRunBytes:      u8
        sampleNumberBytes:  u8
        version:            u8
    }
}

impl FragmentedIndex
{
    // Opens the final random-access index for `trackId`, which is one for this module's writer.
    //
    // Fails if the file is incomplete, unindexed, or has malformed index entries. The movie's
    // initialization and media data are not read. `trackId` must be positive.
    func open(fileName: string, trackId: u32 = 1)->FragmentedIndex fail
    {
        if not trackId do
            fail BadParameterError{"fragmented MP4 index track ID must be positive"}
        var result: #returntype
        result.source = try ByteSource.openFile(fileName)
        let size = result.source.size()
        if size < 48 do
            fail InvalidFormatError{"fragmented MP4 has no final random-access index"}

        try result.source.seek(size - 16)
        if try result.source.readBigEndian'u32() != 16 or
           try result.source.readBigEndian'u32() != IndexOffsetId or
           try result.source.readBigEndian'u32() != 0 do
            fail InvalidFormatError{"fragmented MP4 has no final random-access index"}
        let randomAccessSize = try result.source.readBigEndian'u32()
        if randomAccessSize < 48 or randomAccessSize > size do
            fail InvalidFormatError{"fragmented MP4 random-access size is invalid"}
        result.randomAccessOffset = size - randomAccessSize
        if result.randomAccessOffset < 8 do
            fail InvalidFormatError{"fragmented MP4 random-access box has no preceding movie"}
        try result.source.seek(result.randomAccessOffset)
        let randomAccess = try readBox(&result.source, size)
        if randomAccess.kind != FragmentRandomAccessId or randomAccess.end != size do
            fail InvalidFormatError{"fragmented MP4 random-access box is invalid"}

        var found = false
        while result.source.position() < size - 16
        {
            let child = try readBox(&result.source, size)
            if child.end > size - 16 do
                fail InvalidFormatError{"fragmented MP4 random-access child overlaps its footer"}
            if child.kind == IndexTrackAccessId
            {
                if child.end - child.data < 16 do
                    fail InvalidFormatError{"fragmented MP4 track access header is incomplete"}
                let fullBox      = try result.source.readBigEndian'u32()
                let indexedTrack = try result.source.readBigEndian'u32()
                let lengths      = try result.source.readBigEndian'u32()
                let count        = try result.source.readBigEndian'u32()
                if indexedTrack == trackId
                {
                    if found or (fullBox != 0 and fullBox != 0x01000000) or lengths >> 6 != 0 do
                        fail InvalidFormatError{"fragmented MP4 track access description is invalid"}
                    result.version            = cast(u8, fullBox >> 24)
                    result.trackFragmentBytes = cast(u8, ((lengths >> 4) & 3) + 1)
                    result.trackRunBytes      = cast(u8, ((lengths >> 2) & 3) + 1)
                    result.sampleNumberBytes  = cast(u8, (lengths & 3) + 1)
                    result.entrySize          = cast(u32,
                                                     (result.version == 1 ? 16 : 8) +
                                                     result.trackFragmentBytes + result.trackRunBytes + result.sampleNumberBytes)
                    result.tableOffset = result.source.position()
                    result.count       = count
                    if count > (child.end - result.tableOffset) / result.entrySize or
                       cast(u64, count) * result.entrySize != child.end - result.tableOffset do
                        fail InvalidFormatError{"fragmented MP4 track access entry table is incomplete"}
                    found = true
                }
            }

            try result.source.seek(child.end)
        }

        if not found do
            fail UnsupportedFormatError{"fragmented MP4 has no random-access index for this track"}

        var previousTime = 0'u64
        for index in result.count
        {
            let point = try result.readPoint(index)
            if (index and point.decodeTime <= previousTime) or
               point.moofOffset > result.randomAccessOffset - 8 or
               not point.trackFragmentNumber or
               not point.trackRunNumber or
               not point.sampleNumber do
                fail InvalidFormatError{"fragmented MP4 random-access entry is invalid"}
            previousTime = point.decodeTime
        }

        return result
    }

    // Returns the number of indexed key frames.
    mtd const entryCount()->u32 => .count

    // Reads one indexed key-frame location; `index` is zero based.
    mtd point(index: u32)->FragmentedSeekPoint fail
    {
        if index >= .count do
            fail BadParameterError{"fragmented MP4 random-access index is outside its entries"}
        let result = try .readPoint(index)
        try .source.seek(result.moofOffset + 4)
        if try .source.readBigEndian'u32() != FragmentId do
            fail InvalidFormatError{"fragmented MP4 random-access entry does not point to a fragment"}
        return result
    }

    // Finds the last key frame at or before `decodeTime`; returns false before the first one.
    //
    // The query uses the track's decode-time ticks. On success, `point` receives a file offset
    // suitable for starting a fragment scan.
    mtd tryFindAtOrBefore(decodeTime: u64, point: *FragmentedSeekPoint)->bool fail
    {
        if not .count do
            return false
        var low  = 0'u32
        var high = .count
        while low < high
        {
            let middle    = low + (high - low) / 2
            let candidate = try .readPoint(middle)
            if candidate.decodeTime <= decodeTime do
                low = middle + 1
            else do
                high = middle
        }

        if not low do
            return false
        point[] = try .point(low - 1)
        return true
    }

    // Finds the first indexed key frame at or after `decodeTime`.
    //
    // Returns false after the final entry. The query uses the indexed track's decode-time ticks;
    // the result is suitable for starting a fragment scan when it names the first video sample.
    mtd tryFindAtOrAfter(decodeTime: u64, point: *FragmentedSeekPoint)->bool fail
    {
        var low  = 0'u32
        var high = .count
        while low < high
        {
            let middle    = low + (high - low) / 2
            let candidate = try .readPoint(middle)
            if candidate.decodeTime < decodeTime do
                low = middle + 1
            else do
                high = middle
        }

        if low == .count do
            return false
        point[] = try .point(low)
        return true
    }

    // Releases the indexed file; repeated calls do nothing.
    mtd close() => .source.close()
}

private impl FragmentedIndex
{
    mtd readNumber(bytes: u8)->u32 fail
    {
        var value = 0'u32
        for bytes do
            value = (value << 8) | try .source.readBigEndian'u8()
        return value
    }

    mtd readPoint(index: u32)->FragmentedSeekPoint fail
    {
        try .source.seek(.tableOffset + cast(u64, index) * .entrySize)
        var result: FragmentedSeekPoint
        result.decodeTime          = .version == 1 ? try .source.readBigEndian'u64() : cast(u64, try .source.readBigEndian'u32())
        result.moofOffset          = .version == 1 ? try .source.readBigEndian'u64() : cast(u64, try .source.readBigEndian'u32())
        result.trackFragmentNumber = try .readNumber(.trackFragmentBytes)
        result.trackRunNumber      = try .readNumber(.trackRunBytes)
        result.sampleNumber        = try .readNumber(.sampleNumberBytes)
        return result
    }
}
