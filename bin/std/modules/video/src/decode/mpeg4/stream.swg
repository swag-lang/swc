//! Format: MPEG-4 Part 2 (Simple and Advanced Simple Profile) decoder component.
//! Supported: Rectangular 8-bit 4:2:0 video object layers: I, P and B video object planes, half-sample motion, four motion vectors a macroblock, unrestricted vectors, intra AC/DC prediction, both the H.263 and MPEG quantisers, and packed bitstreams.
//! Not supported: Quarter-sample motion, global motion compensation, interlacing, data partitioning, reversible codes, sprites, and arbitrary object shapes.
//! Role: This file owns an indexed track: display order, seeking, and decoding on demand.
//
#global namespace Mpeg4
#global internal

using Core, Core.Errors, Pixel

// One picture decoded and waiting for its turn to be shown.
private struct Picture
{
    order:  s64     // Stream time for reordered pictures, decode rank for low-delay pictures.
    planes: PlanarFrame
}

// How many pictures can be held back while their order is settled.
//
// A stream refers forward once and no further: every bidirectional plane follows the plane it
// refers to, so one picture held back is enough to know which comes first. One sample can carry
// two of them, and the answer is emitted after the fill, so four slots cover the widest moment.
private const HeldPictures = 4'u64

// Drives an indexed MPEG-4 Part 2 track independently of its container.
//
// Low-delay pictures are ready in decode order. When a stream can reference future pictures,
// its VOP clock gives their display order even if the container only supplies slot numbers.
#[Swag.NoCopy]
struct Mpeg4Stream
{
    decoder:        Decoder
    config:         Array'u8
    frames:         Array'SampleEntry     // Samples in decoding order.
    sampleAtRank:   Array'u32             // Sample of each display rank, by container time.
    payload:        Array'u8
    prefix:         Array'u8     // Bytes the container took off the front of every stored frame.
    queue:          [HeldPictures] Picture
    queued:         u64
    emitRank:       u64     // Display rank of the next picture the queue gives up.
    nextRank:       u64     // Display rank the next call returns.
    nextDecode:     u64     // Decoding-order sample the decoder is about to read.
    started:        bool
    lowDelay:       bool
    slotTimestamps: bool
    firstRepeatEnd: u64     // End of the initial AVI slots that hold its first picture.
    width:          s32
    height:         s32
}

impl Mpeg4Stream
{
    // Configures the decoder from a container's setup headers and installs the samples.
    mtd open(config: const [..] u8, frames: #move Array'SampleEntry, slotTimestamps = false) fail
    {
        if not config.count do
            fail InvalidFormatError{"MPEG-4 track has no decoder configuration"}

        .config.clear()
        .config.add(config)
        try .decoder.configure(.config.toSlice())
        .width          = cast(s32, .decoder.layer.width)
        .height         = cast(s32, .decoder.layer.height)
        .lowDelay       = .decoder.layer.lowDelay
        .slotTimestamps = slotTimestamps
        .installFrames(#move frames)
    }

    // Builds the display order of the window the container holds.
    //
    // A container that indexes progressively hands more samples over as it reads, and every
    // sample it adds is later than the ones already there, so the order of those does not move.
    // Rebuilding it must therefore not disturb a decode already in flight.
    mtd rebuildOrder()
    {
        .sampleAtRank.clear()
        if .slotTimestamps do
            return
        .sampleAtRank.reserve(.frames.count)

        // A stable insertion by presentation time: the tables are short, and equal times must
        // keep the order the container stated.
        for index in .frames.count
        {
            var at = .sampleAtRank.count
            while not .lowDelay and
                  at > 0 and
                  .frames[cast(u64, .sampleAtRank[at - 1])].presentationTime > .frames[index].presentationTime do
                at -= 1
            .sampleAtRank.insertAt(at, cast(u32, index))
        }
    }

    // Installs a window and starts over from its first picture.
    mtd installFrames(frames: #move Array'SampleEntry)
    {
        .frames         = #move frames
        .firstRepeatEnd = 1
        if .slotTimestamps and not .lowDelay
        {
            while .firstRepeatEnd < .frames.count and .frames[.firstRepeatEnd].repeatPrevious do
                .firstRepeatEnd += 1
        }

        .rebuildOrder()
        .nextRank   = 0
        .nextDecode = 0
        .started    = false
        .queued     = 0
        .decoder.reset()
    }

    // Replaces the container window while keeping the configured decoder.
    mtd replaceFrames(frames: #move Array'SampleEntry) fail
    {
        .installFrames(#move frames)
    }

    // Extends the window with samples the reader has since indexed.
    //
    // Nothing about the decode in flight changes: the added samples are later than every one the
    // decoder has read, so the anchors it holds stay the anchors they were.
    mtd appendFrames(frames: const [..] SampleEntry) fail
    {
        if not frames.count do
            return
        .frames.add(frames)
        .rebuildOrder()
    }

    mtd const frameCount()->u64 => .frames.count

    private mtd const sampleIndex(rank: u64)->u64 => .slotTimestamps ? rank : cast(u64, .sampleAtRank[rank])

    mtd const presentationTimeAtRank(rank: u64)->s64
    {
        if rank >= .frames.count do
            return 0
        return .frames[.sampleIndex(rank)].presentationTime
    }

    mtd const isSyncRank(rank: u64)->bool
    {
        let sample = .sampleIndex(rank)
        return sample < .frames.count and .frames[sample].isSync
    }

    // Returns the first display rank at or after `rank` whose sample starts a clean decode.
    // Returns the stream length when no sync sample remains past `rank`.
    mtd const syncRankAt(rank: u64)->u64
    {
        var scan = rank
        while scan < .frames.count and not .isSyncRank(scan) do
            scan += 1
        return Math.min(scan, .frames.count)
    }

    // Returns the last display rank at or before `rank` whose sample starts a clean decode,
    // which is where decoding the picture of `rank` has to begin.
    mtd const decodeStartRank(rank: u64)->u64
    {
        if not .frames.count do
            return 0
        var scan = Math.min(rank, .frames.count - 1)
        while scan > 0 and not .isSyncRank(scan) do
            scan -= 1
        return scan
    }

    // Positions the stream so the next decoded picture has display rank `rank`.
    mtd seekTo(rank: u64)
    {
        if rank == .nextRank do
            return

        // An AVI skip inside the active GOP can continue from its ready pictures and anchors.
        // A new GOP may offer a shorter decode, and backward skips always need new anchors.
        if .started and (not .slotTimestamps or rank < .nextRank or .decodeStartRank(rank) > .emitRank) do
            .started = false
        .nextRank = rank
    }

    mtd releasePending() {}

    // Reads samples until enough pictures are held to know which of them comes first.
    mtd fill(source: *ByteSource) fail
    {
        let lookahead = .lowDelay ? 1'u64 : 2'u64
        while .queued < lookahead and .nextDecode < .frames.count
        {
            let entry = .frames[.nextDecode]

            // Empty AVI slots after the first anchor hold it while the encoder buffers its
            // next picture. In a low-delay stream an empty slot holds the latest anchor.
            if entry.repeatPrevious and (.lowDelay or .nextDecode < .firstRepeatEnd)
            {
                if not .decoder.anchors do
                    break
                .enqueuePicture()
                .nextDecode += 1
                continue
            }

            try readStoredFrame(source, entry, .prefix.toSlice(), &.payload)
            .nextDecode += 1
            .decoder.beginSample()
            while try .decoder.nextPicture(.payload.toSlice())
            {
                if .queued >= HeldPictures do
                    break
                .enqueuePicture()
            }
        }
    }

    private mtd enqueuePicture()
    {
        .decoder.reference().writePlanar(&.queue[.queued].planes)
        .queue[.queued].order = .lowDelay ? cast(s64, (.emitRank + .queued)) : .decoder.pictureTime
        .queued += 1
    }

    // Which held picture is shown first.
    mtd const earliest()->u64
    {
        var at = 0'u64
        for index in .queued where .queue[index].order < .queue[at].order do
            at = index
        return at
    }

    // Gives up one held picture, either to the caller or to the floor.
    mtd release(at: u64, target: *PlanarFrame?)
    {
        // Keep the caller's old plane allocation available for the next queued picture.
        if let output = target do
            Core.swap(output, &.queue[at].planes)
        .queued -= 1
        if at != .queued do
            Core.swap(&.queue[at], &.queue[.queued])
        .emitRank += 1
    }

    private mtd startAtRank(source: *ByteSource) fail
    {
        var start = .decodeStartRank(.nextRank)
        while true
        {
            .decoder.reset()
            .queued     = 0
            .emitRank   = start
            .nextDecode = .sampleIndex(start)
            if not .slotTimestamps or .lowDelay or not start do
                break

            // AVI numbers packed and reordered samples as slots. An I-picture in such a slot
            // can be displayed after B-pictures that depend on the preceding GOP. When starting
            // here those pictures are skipped, so advance the first available display rank.
            try .fill(source)
            .emitRank += .decoder.leadingB
            if .emitRank <= .nextRank do
                break

            // The requested picture needs the preceding GOP's final anchor as well as this I.
            start = .decodeStartRank(start - 1)
        }

        .started = true
    }

    // Decodes forward until the picture of the current rank is reconstructed.
    private mtd nextDisplaySlot(source: *ByteSource)->u64 fail
    {
        if .nextRank >= .frames.count do
            fail InvalidFormatError{"MPEG-4 stream has no picture at the requested position"}

        // A picture that is not a clean decode point needs everything back to the last one.
        if not .started or .emitRank > .nextRank do
            try .startAtRank(source)

        while true
        {
            // A failed sample may have changed the reference pictures before reporting an error.
            .started = false
            try .fill(source)
            if not .queued do
                fail InvalidFormatError{"MPEG-4 stream ends before the picture asked for"}
            .started = true

            let at = .earliest()
            if .emitRank == .nextRank do
                return at

            // A picture shown before the one asked for is decoded for what it anchors, not for
            // itself.
            .release(at, null)
        }
    }

    mtd decodeNextPlanes(source: *ByteSource, target: *PlanarFrame) fail
    {
        let at = try .nextDisplaySlot(source)
        .release(at, target)
        .nextRank += 1
    }

    // Reads only the independent picture named by a container sync slot.
    mtd decodeSyncPicture(source: *ByteSource, rank: u64, target: *Image)->bool fail
    {
        .started = false
        .queued  = 0
        .decoder.reset()
        try readStoredFrame(source, .frames[.sampleIndex(rank)], .prefix.toSlice(), &.payload)
        .decoder.beginSample()
        if not (try .decoder.nextPicture(.payload.toSlice())) do
            return false

        .decoder.reference().writePlanar(&.queue[0].planes)
        .queue[0].planes.view().convertToRgb(target)
        return true
    }

    // Convert the queued planes in place so the slot keeps its storage for the next picture.
    mtd decodeNext(source: *ByteSource, target: *Image) fail
    {
        let at = try .nextDisplaySlot(source)
        .queue[at].planes.view().convertToRgb(target)
        .release(at, null)
        .nextRank += 1
    }
}
