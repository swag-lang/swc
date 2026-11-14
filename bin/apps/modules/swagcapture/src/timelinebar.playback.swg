#global internal

using Core, Pixel, Video

impl TimelineBar
{
    // Repositions the independent decoder and discards pictures from the previous passage.
    mtd requestVideoFrames(capture: *Capture, frame: u64)
    {
        Sync.scopedLock(&.videoLock)
        .videoGeneration += 1
        .videoPath = String.from(Capture.mediaPathOf(capture.file, .Video))
        .videoFrom = frame
        .videoNext = frame
        .videoCount = capture.frames!.frameCount()
        .videoActive = true
        .videoFailed = false
        .videoReady.clear()
        .videoFree.clear()
        for slot in TimelineVideoSlots where not .videoBusy or slot != .videoBusySlot do
            .videoFree.add(cast(u32, slot))
        .videoWake.signal()
    }

    // Leaves an in-flight decode alone; its generation check discards its result.
    mtd stopVideoFrames()
    {
        if Swag.jit() do
            return
        Sync.scopedLock(&.videoLock)
        .videoGeneration += 1
        .videoActive = false
        .videoReady.clear()
        .videoFree.clear()
    }

    // Closes every reader of a capture before the library moves its media to the trash.
    mtd releaseCaptureMedia(file: string)
    {
        let media = Capture.mediaPathOf(file, .Video)
        let displayed = .viewCapture and .viewCapture.isStoredIn(file)
        var decoding: bool
        scope
        {
            Sync.scopedLock(&.videoLock)
            decoding = Path.equals(.videoPath, media)
        }
        if not displayed and not decoding and not Path.equals(.audioPath, media) do
            return

        .stop(materialize: false)
        .disposeAudio()
        .clearThumbnails()
        if not Swag.jit() and .videoTask.isPending()
        {
            scope
            {
                Sync.scopedLock(&.videoLock)
                .videoReleaseRequested = true
            }
            .videoWake.signal()
            .videoReleased.wait()
        }
        if displayed do
            .viewCapture = null
    }

    mtd videoDecodeFailed()->bool
    {
        Sync.scopedLock(&.videoLock)
        return .videoFailed
    }

    // Begin the clock only when enough pictures are ready to cover a decode burst.
    mtd videoBuffered()->bool
    {
        Sync.scopedLock(&.videoLock)
        let remaining = .videoCount - .videoFrom
        return .videoReady.count >= Math.min(4'u64, remaining)
    }

    // Shows the newest decoded picture the clock has reached and reuses its old plane storage.
    mtd presentVideoFrame(capture: *Capture, target: u64)->bool
    {
        var shown: bool
        scope
        {
            Sync.scopedLock(&.videoLock)
            while .videoReady.count > 1 and .videoSlots[.videoReady[1]].index <= target
            {
                .videoFree.add(.videoReady[0])
                .videoReady.removeAtOrdered(0)
            }

            if not .videoReady.isEmpty() and .videoSlots[.videoReady[0]].index <= target
            {
                let slot = .videoReady[0]
                .videoReady.removeAtOrdered(0)
                capture.presentPlaybackFrame(&.videoSlots[slot].planes, .videoSlots[slot].index)
                .videoFree.add(slot)
                shown = true
            }
        }

        if shown do
            .videoWake.signal()
        return shown
    }

    // Exactly one worker owns the reader; the UI only exchanges completed plane buffers.
    private mtd decodeOneVideo(reader: *Video.Reader, readerPath: *String)->bool
    {
        var slot, generation: u32
        var index: u64
        var path: String
        scope
        {
            Sync.scopedLock(&.videoLock)
            if not .videoActive or .videoFailed or .videoFree.isEmpty() or .videoNext >= .videoCount do
                return false
            slot = .videoFree.popBack()
            index = .videoNext
            generation = .videoGeneration
            path = String.from(.videoPath)
            .videoNext += 1
            .videoBusy = true
            .videoBusySlot = slot
        }

        var failed: bool
        catch
        {
            if not reader.isOpen() or not Path.equals(readerPath.toString(), path.toString())
            {
                if reader.isOpen() do
                    reader.close()
                reader[] = try Video.Reader.open(path.toString(), pictureOnly: true)
                readerPath[] = String.from(path)
            }
            try reader.decodeFramePlanesInto(&.videoSlots[slot].planes, index)
        }
        {
            failed = true
        }

        Sync.scopedLock(&.videoLock)
        .videoBusy = false
        if generation != .videoGeneration
        {
            .videoFree.add(slot)
            return true
        }
        if failed
        {
            .videoFailed = true
            .videoFree.add(slot)
            return false
        }
        .videoSlots[slot].index = index
        .videoReady.add(slot)
        return true
    }
}

// The same Video.Reader used by Swag Scope decodes ahead on its own executor.
func runTimelineVideoDecoder(bar: *TimelineBar)
{
    var reader: Video.Reader
    var path: String
    while not Swag.isCancelled()
    {
        bar.videoWake.wait()
        while not Swag.isCancelled() and bar.decodeOneVideo(&reader, &path) {}
        var releaseRequested: bool
        scope
        {
            Sync.scopedLock(&bar.videoLock)
            releaseRequested = bar.videoReleaseRequested
        }
        if releaseRequested
        {
            if reader.isOpen() do
                reader.close()
            path.clear()
            Sync.scopedLock(&bar.videoLock)
            bar.videoReleaseRequested = false
            bar.videoReleased.signal()
        }
    }
    if reader.isOpen() do
        reader.close()
}
