using Core, Video

const TimelineVideoSlots = 5     // Five 4K YUV420 pictures stay below 64 MiB.

// One decoded picture and the frame it shows.
struct TimelineVideoSlot
{
    index:  u64
    planes: PlanarFrame
}

// Decodes the pictures of the timeline's video ahead of its playback clock, on its own executor.
//
// The same Video.Reader used by Swag Scope decodes on one worker, which alone owns it; the
// interface thread only exchanges completed plane buffers. Every request starts a new generation,
// and a picture decoded for an older one is discarded.
struct TimelineVideoDecoder
{
    slots:            [TimelineVideoSlots] TimelineVideoSlot
    ready:            StaticArray'(u32, TimelineVideoSlots)     // Decoded slots, in frame order.
    free:             StaticArray'(u32, TimelineVideoSlots)
    lock:             Swag.Mutex
    wake:             Sync.Event
    released:         Sync.Event
    task:             Swag.Task
    executor:         Swag.Executor
    path:             String
    generation:       u32
    firstFrame:       u64     // Frame the current request starts from.
    nextFrame:        u64     // Next frame the worker decodes.
    frameCount:       u64
    active:           bool
    failed:           bool
    busy:             bool     // The worker is decoding into `busySlot`.
    busySlot:         u32
    releaseRequested: bool
}

impl TimelineVideoDecoder
{
    // Starts the worker. `notifier` runs on the worker's thread once it has ended.
    mtd start(notifier: func||())
    {
        .wake.init()
        .released.init()
        .executor.start()
        .task.submit(func|decoder = me|() { decoder.run() }, notifier, executor: &.executor)
    }

    // Ends the worker and releases what it waited on.
    mtd close()
    {
        if not .task.isPending() do
            return
        .task.cancel()
        .wake.signal()
        .task.wait()
        .executor.close()
        .wake.release()
        .released.release()
    }

    // Repositions the decoder on `frame` of the video of `capture` and discards pictures from the
    // previous passage.
    mtd request(capture: *Capture, frame: u64)
    {
        Sync.scopedLock(&.lock)
        .generation += 1
        .path       = Capture.mediaPathOf(capture.file, .Video)
        .firstFrame = frame
        .nextFrame  = frame
        .frameCount = capture.frames!.frameCount()
        .active     = true
        .failed     = false
        .ready.clear()
        .free.clear()
        for slot in TimelineVideoSlots where not .busy or slot != .busySlot do
            .free.add(cast(u32, slot))
        .wake.signal()
    }

    // Leaves an in-flight decode alone; its generation check discards its result.
    mtd stop()
    {
        if Swag.jit() do
            return
        Sync.scopedLock(&.lock)
        .generation += 1
        .active     = false
        .ready.clear()
        .free.clear()
    }

    // Returns whether the decoder was last asked for the video at `path`.
    mtd isDecoding(path: string)->bool
    {
        Sync.scopedLock(&.lock)
        return Path.equals(.path, path)
    }

    // Has the worker close its reader, and waits until it has, so the file can be moved.
    mtd releaseReader()
    {
        if Swag.jit() or not .task.isPending() do
            return
        scope
        {
            Sync.scopedLock(&.lock)
            .releaseRequested = true
        }

        .wake.signal()
        .released.wait()
    }

    // Returns whether a picture could not be decoded since the last request.
    mtd hasFailed()->bool
    {
        Sync.scopedLock(&.lock)
        return .failed
    }

    // Returns whether enough pictures are ready to cover a decode burst, so the clock can begin.
    mtd isBuffered()->bool
    {
        Sync.scopedLock(&.lock)
        let remaining = .frameCount - .firstFrame
        return .ready.count >= Math.min(4'u64, remaining)
    }

    // Shows on `capture` the newest decoded picture the clock has reached at frame `target`, and
    // hands its old plane storage back to the worker. Returns whether a picture was shown.
    mtd present(capture: *Capture, target: u64)->bool
    {
        var shown: bool
        scope
        {
            Sync.scopedLock(&.lock)
            while .ready.count > 1 and .slots[.ready[1]].index <= target
            {
                .free.add(.ready[0])
                .ready.removeAtOrdered(0)
            }

            if not .ready.isEmpty() and .slots[.ready[0]].index <= target
            {
                let slot = .ready[0]
                .ready.removeAtOrdered(0)
                capture.presentPlaybackFrame(&.slots[slot].planes, .slots[slot].index)
                .free.add(slot)
                shown = true
            }
        }

        if shown do
            .wake.signal()
        return shown
    }
}

private impl TimelineVideoDecoder
{
    // Decodes the pictures asked for until none is wanted or no slot is free.
    mtd run()
    {
        var reader:     Video.Reader
        var readerPath: String
        while not Swag.isCancelled()
        {
            .wake.wait()
            while not Swag.isCancelled() and .decodeOne(&reader, &readerPath) {}

            var releaseRequested: bool
            scope
            {
                Sync.scopedLock(&.lock)
                releaseRequested = .releaseRequested
            }

            if releaseRequested
            {
                if reader.isOpen() do
                    reader.close()
                readerPath.clear()
                Sync.scopedLock(&.lock)
                .releaseRequested = false
                .released.signal()
            }
        }

        if reader.isOpen() do
            reader.close()
    }

    // Decodes the next picture into a free slot. Returns whether the worker can go on.
    mtd decodeOne(reader: *Video.Reader, readerPath: *String)->bool
    {
        var slot, generation: u32
        var index:  u64
        var reopen: bool
        scope
        {
            Sync.scopedLock(&.lock)
            if not .active or .failed or .free.isEmpty() or .nextFrame >= .frameCount do
                return false
            slot       = .free.popBack()
            index      = .nextFrame
            generation = .generation
            .nextFrame += 1
            .busy      = true
            .busySlot  = slot

            // The path only changes with a request: it is copied then, not for every picture.
            reopen = not reader.isOpen() or not Path.equals(readerPath.toString(), .path)
            if reopen do
                readerPath[] = String.from(.path)
        }

        var failed: bool
        catch
        {
            if reopen
            {
                if reader.isOpen() do
                    reader.close()
                reader[] = try Video.Reader.open(readerPath.toString(), pictureOnly: true)
            }

            try reader.decodeFramePlanesInto(&.slots[slot].planes, index)
        }
        {
            failed = true
        }

        Sync.scopedLock(&.lock)
        .busy = false
        if generation != .generation
        {
            .free.add(slot)
            return true
        }

        if failed
        {
            .failed = true
            .free.add(slot)
            return false
        }

        .slots[slot].index = index
        .ready.add(slot)
        return true
    }
}
