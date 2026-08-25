#global namespace Hevc
#global internal

using Core, Core.Errors, Pixel

// How far a stream may reorder before the reader gives up on it.
//
// The format allows sixteen pictures in the buffer, and a picture waiting for display holds one;
// past that the stream is not reordering, it is malformed.
private const MaxReorderDepth = 17'u64

// One reconstructed picture waiting for its display turn.
private struct PendingFrame
{
    frame: #null *Frame
    rank:  u64
}

// Drives an indexed H.265 stream independently of its container.
//
// The container hands over the access units of one track in decoding order with the presentation
// time of each; this resolves display order from those times, decodes on demand, and holds the
// pictures a reordered stream produces early.
#[Swag.NoCopy]
struct HevcStream
{
    decoder:      Decoder
    config:       Array'u8
    lengthSize:   u32 = 4
    frames:       Array'SampleEntry     // Samples in decode order.
    rankOfSample: Array'u32             // Display rank of each decode-order sample.
    sampleAtRank: Array'u32             // Decode-order sample of each display rank.
    syncFlags:    Array'u8
    pending:      Array'PendingFrame
    payload:      Array'u8

    nextDecode:  u64                    // Next sample to decode.
    nextRank:    u64                    // Display rank the next decode call returns.
    skipBefore:  u64
    decodeLimit: u64 = Swag.U64.Max
    reachedEnd:  bool
    width:       s32
    height:      s32
}

impl HevcStream
{
    // Configures the decoder from a container's decoder configuration and installs the samples.
    mtd open(config: const [..] u8, frames: Array'SampleEntry) fail
    {
        if !@countof(config) do
            fail InvalidFormatError{"H.265 track has no decoder configuration"}

        .config.clear()
        .config.add(config)
        try .configure()
        .installFrames(#move frames)
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: Array'SampleEntry) fail
    {
        .releasePending()
        .decoder.reset()
        try .configure()

        .nextDecode  = 0
        .nextRank    = 0
        .skipBefore  = 0
        .decodeLimit = Swag.U64.Max
        .reachedEnd  = false
        .installFrames(#move frames)
    }

    // Reads the parameter sets a container carries beside the stream, ISO/IEC 14496-15.
    private mtd configure() fail
    {
        let config = .config.toSlice()
        if @countof(config) < 23 do
            fail InvalidFormatError{"H.265 decoder configuration is truncated"}
        if config[0] != 1 do
            fail UnsupportedFormatError{"H.265 decoder configuration uses an unknown version"}

        .lengthSize = cast(u32) (config[21] & 3) + 1
        let arrays  = cast(u32) config[22]

        var offset = 23'u64
        for arrays
        {
            if offset + 3 > @countof(config) do
                fail InvalidFormatError{"H.265 decoder configuration is truncated"}
            let count = (cast(u32) config[offset + 1] << 8) | cast(u32) config[offset + 2]
            offset += 3

            for count
            {
                if offset + 2 > @countof(config) do
                    fail InvalidFormatError{"H.265 decoder configuration is truncated"}
                let length = (cast(u64) config[offset] << 8) | cast(u64) config[offset + 1]
                offset += 2
                if offset + length > @countof(config) do
                    fail InvalidFormatError{"H.265 decoder configuration is truncated"}
                discard try .decoder.readNalUnit(config[offset until offset + length])
                offset += length
            }
        }

        // The geometry the reader reports comes from the sequence the sets describe.
        var sequence: #null const *Sps
        for index in 16'u32 where .decoder.sps[index].valid
        {
            sequence = &.decoder.sps[index]
            break
        }

        if !sequence do
            fail InvalidFormatError{"H.265 decoder configuration has no sequence parameter set"}
        .width  = cast(s32) sequence!.visibleWidth()
        .height = cast(s32) sequence!.visibleHeight()
    }

    // Builds the display order of the installed samples from their presentation times.
    private mtd installFrames(frames: Array'SampleEntry)
    {
        .frames = #move frames
        let count = .frames.count

        // Real streams are nearly sorted already, off by at most the reorder depth, so inserting
        // each sample into place costs a bounded walk rather than a sort.
        var order: Array'u32
        order.reserve(count)
        for index in count
        {
            var position = order.count
            while position > 0 and .frames[cast(u64) order[position - 1]].presentationTime > .frames[index].presentationTime do
                position -= 1
            order.insertAt(position, cast(u32) index)
        }

        .rankOfSample.clear()
        .sampleAtRank.clear()
        .rankOfSample.resize(count)
        .sampleAtRank.resize(count)
        for rank in order.count
        {
            .sampleAtRank[rank] = order[rank]
            .rankOfSample[cast(u64) order[rank]] = cast(u32) rank
        }

        .syncFlags.clear()
        .syncFlags.resize(count)
        for index in count where .frames[index].isSync do
            .syncFlags[index] = 1
        if count do
            .syncFlags[0] = 1
    }

    // Extends a running stream with samples the container has since indexed.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        if !@countof(frames) do
            return

        var merged: Array'SampleEntry
        merged.reserve(.frames.count + @countof(frames))
        for entry in .frames do
            merged.add(entry[])
        for entry in frames do
            merged.add(entry[])

        let decode = .nextDecode
        let rank   = .nextRank
        let limit  = .decodeLimit
        let skip   = .skipBefore
        .installFrames(#move merged)
        .nextDecode  = decode
        .nextRank    = rank
        .decodeLimit = limit
        .skipBefore  = skip
    }

    mtd opDrop()
    {
        .releasePending()
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    mtd const syncRankAt(rank: u64)->u64
    {
        var scan = rank
        while scan < .frames.count
        {
            if .syncFlags[cast(u64) .sampleAtRank[scan]] != 0 do
                return scan
            scan += 1
        }

        return .frames.count
    }

    // Returns the container presentation timestamp of one display-order picture.
    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        Debug.assert(rank < .sampleAtRank.count)
        return .frames[cast(u64) .sampleAtRank[rank]].presentationTime
    }

    // Positions the stream so the next decoded frame has display rank `rank`.
    mtd seekTo(rank: u64)
    {
        if rank == .nextRank do
            return

        let sample = cast(u64) .sampleAtRank[rank]
        var sync   = sample
        while sync > 0 and .syncFlags[sync] == 0 do
            sync -= 1

        var alreadyPending = false
        for entry in .pending where entry.rank == rank
        {
            alreadyPending = true
            break
        }

        if rank < .nextRank or (!alreadyPending and sync > .nextDecode)
        {
            .releasePending()
            .decoder.reset()
            discard catch .configure()
            .nextDecode = sync
            .reachedEnd = false
        }
        else
        {
            .releasePendingBelow(rank)
        }

        .skipBefore  = rank
        .decodeLimit = sample + 1
        .nextRank    = rank
    }

    // Releases every pending picture whose display rank precedes `rank`.
    mtd releasePendingBelow(rank: u64)
    {
        var index = 0'u64
        while index < .pending.count
        {
            if .pending[index].rank < rank
            {
                .release(.pending[index].frame!)
                .pending.removeAtOrdered(index)
                continue
            }

            index += 1
        }
    }

    // Releases every picture waiting for display.
    mtd releasePending()
    {
        for entry in .pending do
            .release(entry.frame!)
        .pending.clear()
    }

    // Reports one picture as shown, so the decoded picture buffer can take its storage back.
    //
    // The container states display order, so the buffer's own output process of clause C.5.2
    // never runs here. A picture therefore stops being needed for output exactly when this stream
    // is done with it, and until it does the buffer counts it as occupied.
    private mtd release(frame: *Frame)
    {
        frame.outputNeeded = false
        Atomic.exchange(&frame.heldByCaller, 0)
    }

    // Decodes the picture with the current display rank and hands over its planes unconverted.
    mtd decodeNextPlanes(source: *Source, target: *PlanarFrame) fail
    {
        let frame = try .nextDisplayFrame(source)
        let sequence = .decoder.activeSps
        if sequence do
            frame.writePlanar(target, sequence!)
        .release(frame)
    }

    // Decodes the picture with the current display rank and converts it to packed colour.
    mtd decodeNext(source: *Source, target: *Image) fail
    {
        var planes: PlanarFrame
        try .decodeNextPlanes(source, &planes)
        planes.view().convertToRgb(target)
    }

    // Decodes until the picture of the current display rank is available.
    private mtd nextDisplayFrame(source: *Source)->*Frame fail
    {
        for
        {
            for index in .pending.count where .pending[index].rank == .nextRank
            {
                let frame = .pending[index].frame!
                .pending.removeAtOrdered(index)
                .nextRank   += 1
                .decodeLimit = Swag.U64.Max
                return frame
            }

            if .nextDecode >= .frames.count or .nextDecode >= .decodeLimit
            {
                if .reachedEnd or .nextDecode >= .frames.count do
                    fail InvalidFormatError{"H.265 stream has no picture for the requested position"}
                .decodeLimit = Swag.U64.Max
            }

            let sample = .nextDecode
            .nextDecode += 1
            if .nextDecode >= .frames.count do
                .reachedEnd = true

            let entry = .frames[sample]
            .payload.resize(entry.size)
            try source.seek(entry.offset)
            try source.readExact(.payload.toSlice())

            let picture = try .decodeAccessUnit(.payload.toSlice())
            if !picture do
                continue

            let rank = cast(u64) .rankOfSample[sample]
            if rank < .skipBefore
            {
                // A picture decoded only to reach the requested one is never shown.
                .release(picture!)
                continue
            }

            Atomic.exchange(&picture!.heldByCaller, 1)
            .pending.add({picture, rank})
            if .pending.count > MaxReorderDepth do
                fail InvalidFormatError{"H.265 stream reorders more pictures than the buffer holds"}
        }
    }

    // Decodes one length-prefixed access unit and returns the picture it completed.
    private mtd decodeAccessUnit(data: const [..] u8)->#null *Frame fail
    {
        var offset = 0'u64
        while offset + cast(u64) .lengthSize <= @countof(data)
        {
            var length = 0'u64
            for index in .lengthSize do
                length = (length << 8) | cast(u64) data[offset + cast(u64) index]
            offset += cast(u64) .lengthSize
            if !length or offset + length > @countof(data) do
                fail InvalidFormatError{"H.265 access unit holds a truncated network abstraction layer unit"}

            discard try .decoder.readNalUnit(data[offset until offset + length])
            offset += length
        }

        return try .decoder.finishPicture()
    }
}
