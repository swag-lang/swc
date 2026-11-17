#global public

using Core, Core.Errors, Pixel

// Validates dimensions before a native source or image storage is allocated.
internal func validateSourceOptions(options: SourceOptions) fail
{
    if options.width <= 0 or options.height <= 0 or options.width > 0x7FFFFFFF's32 / 4 do
        fail BadParameterError{"screen source needs positive dimensions"}
}

// Converts QPC ticks to the microsecond units used by Core.Time.
internal func qpcTicksToMicroseconds(ticks, frequency: u64)->u64
{
    let divisor = Math.max(1'u64, frequency)
    let seconds = ticks / divisor
    let remainder = ticks % divisor
    let scaled = seconds * 1_000_000 + (remainder * 1_000_000) / divisor
    return frequency ? scaled : 0
}

internal func frameAgeAt(now, capturedAt: u64)->u64
{
    if not capturedAt do
        return 0
    return now - capturedAt
}

#[Swag.Inline]
internal func copyFrameBytes(destination: [*] u8, source: const [*] u8, byteCount: u64)
{
    if byteCount < 8 * 1_048_576
    {
        Memory.copy(destination, source, byteCount)
        return
    }

    let chunkSize = 1_048_576'u64
    let chunkCount = (byteCount + chunkSize - 1) / chunkSize
    parallel for |destination, source, byteCount, chunkSize| chunk in chunkCount
    {
        let offset = chunk * chunkSize
        Memory.copy(destination + offset, source + offset,
                    Math.min(chunkSize, byteCount - offset))
    }
}

// One physical desktop area to capture; dimensions must be positive.
struct SourceOptions
{
    public x:             s32     // Left edge in physical desktop pixels.
    public y:             s32     // Top edge in physical desktop pixels.
    public width:         s32     // Width in physical pixels.
    public height:        s32     // Height in physical pixels.
    public includeCursor: bool    // Composites the pointer over the captured desktop pixels.
}

// Cumulative acquisition costs for one [[Screen.Source]], in microseconds.
struct SourceMetrics
{
    public acquiredFrames:       u64 // Frames read from the native source, including pixel-identical images.
    public unchangedFrames:      u64 // Polls where a backend detected no pixel change in the selected image; may overlap acquisitions.
    public coalescedUpdates:      u64 // Desktop updates combined before acquisition, when reported by the source.
    public acquireMicroseconds:  u64 // Time waiting for a native frame.
    public maxAcquireMicroseconds: u64 // Longest single native acquisition wait.
    public changeDetectionMicroseconds: u64 // CPU time checking pixels or metadata for selected-image changes.
    public readbackMicroseconds: u64 // CPU time submitting and waiting for native pixel readbacks.
    public maxReadbackMicroseconds: u64 // Longest single readback, including deferred CPU waits.
    public deferredReadbacks:     u64 // Readback polls deferred while the GPU still owned the pixels.
    public copyMicroseconds:     u64 // Time copying native pixels into owned storage.
    public outputMicroseconds:   u64 // Native cache-output time, zero for current backends.
    public composeMicroseconds:  u64 // Time composing output images, cursor overlays and copies into the caller's image.
    public partialFrames:        u64 // Frames read through a region smaller than the selected output.
    public multiRectFrames:      u64 // Frames read through several bounded desktop update regions.
    public copiedPixels:         u64 // Pixels converted from native readback storage, including full frames.
    public mirroredPixels:       u64 // Pixels incrementally copied from the native cache into a stable caller image.
}

// Owns a live desktop source and its most recent image.
//
// The source must be used and destroyed on the thread that opened it. `grabInto` retains
// bounded storage at the selected dimensions and may reuse the previous image when the
// desktop has not presented a new frame.
#[Swag.Opaque, Swag.NoCopy]
struct Source
{
    internal
    {
        options:  SourceOptions
        sources:  Array'(*NativeSource)
        pictures: Array'Image
        composed: Image
        composeMicroseconds: u64
        lastFrameCaptureTime: u64
        lastFramePresentationTime: u64
        mirroredPixels:       u64
        mirroredImage:        u64
        mirroredStorage:      u64
        mirrorReady:          bool
        #static if #os == Swag.TargetOs.Windows
        {
            cursorDC:       Win32.HDC
            cursorBitmap:   Win32.HBITMAP
            cursorOldBitmap: Gdi32.HGDIOBJ
            cursorPixels:   *void?
            cursorRenderedPixels: Array'u8
            cursorRenderedLeft, cursorRenderedTop: s32
            cursorRenderedRight, cursorRenderedBottom: s32
            cursorTargetImage:   u64
            cursorTargetStorage: u64
            cursorTargetReady:   bool
        }
        #static if #os == Swag.TargetOs.Linux
        {
            x11TargetImage:   u64
            x11TargetStorage: u64
            x11TargetReady:   bool
        }
    }
}

impl Source
{
    // Opens a native source for one physical desktop area.
    //
    // Rejects invalid dimensions, unavailable displays and capture permission failures.
    func open(options: SourceOptions)->Source fail
    {
        try validateSourceOptions(options)
        var result: #returntype
        result.options = options
        #static if #os == Swag.TargetOs.Windows
        {
            let right = cast(s64, options.x) + options.width
            let bottom = cast(s64, options.y) + options.height
            var covered: u64
            for monitor in Env.getMonitors()
            {
                let bounds = monitor.physicalBounds
                let left = Math.max(cast(s64, options.x), cast(s64, bounds.x))
                let top = Math.max(cast(s64, options.y), cast(s64, bounds.y))
                let partRight = Math.min(right, cast(s64, bounds.right()))
                let partBottom = Math.min(bottom, cast(s64, bounds.bottom()))
                if partRight <= left or partBottom <= top do
                    continue
                let part = SourceOptions{cast(s32, left), cast(s32, top),
                                         cast(s32, partRight - left), cast(s32, partBottom - top),
                                         options.includeCursor}
                try result.addPart(part)
                covered += cast(u64, part.width) * cast(u64, part.height)
            }
            if covered == 0 do
                fail UnsupportedFormatError{"screen capture area has no available display"}
        }
        else
        {
            try result.addPart(options)
        }
        return result
    }

    // Opens a source for one currently enumerated physical monitor.
    //
    // `monitorIndex` uses the current order from [[Core.Env.getMonitors]] and is not a persistent display identifier.
    // The source captures that monitor's full physical bounds and can fail if the display is unavailable.
    // `includeCursor` requests pointer composition where supported and defaults to false.
    func openMonitor(monitorIndex: u64, includeCursor: bool = false)->Source fail
    {
        let monitors = Env.getMonitors()
        if monitorIndex >= monitors.count do
            fail BadParameterError{"screen monitor index is unavailable"}
        return try .openMonitor(monitors[monitorIndex], includeCursor)
    }

    // Opens a source for a monitor value returned by [[Core.Env.getMonitors]].
    //
    // The value is a snapshot of physical bounds, not a persistent display identifier. The source can fail
    // if those bounds are no longer available. `includeCursor` requests pointer composition where supported
    // and defaults to false.
    func openMonitor(monitor: Env.Monitor, includeCursor: bool = false)->Source fail
    {
        let bounds = monitor.physicalBounds
        return try .open({cast(s32, bounds.x), cast(s32, bounds.y), cast(s32, bounds.width),
                          cast(s32, bounds.height), includeCursor})
    }

    // Opens the monitor containing a physical desktop point, or the nearest monitor in a gap.
    // Selection follows [[Core.Env.monitorForPoint]]'s physical-coordinate policy.
    // `includeCursor` requests pointer composition and defaults to false.
    func openMonitorAt(point: Math.Point, includeCursor: bool = false)->Source fail
    {
        let monitor = Env.monitorForPoint(point)
        if monitor.physicalBounds.width <= 0 or monitor.physicalBounds.height <= 0 do
            fail UnsupportedFormatError{"screen monitors are unavailable"}
        return try .openMonitor(monitor, includeCursor)
    }

    // Opens a source for the current virtual desktop bounds.
    //
    // The rectangle includes gaps between monitors. It can fail when no desktop bounds are available.
    // `includeCursor` requests pointer composition where supported and defaults to false.
    func openDesktop(includeCursor: bool = false)->Source fail
    {
        let monitors = Env.getMonitors()
        if monitors.isEmpty() do
            fail UnsupportedFormatError{"screen virtual desktop is unavailable"}
        var left = monitors[0].physicalBounds.x
        var top = monitors[0].physicalBounds.y
        var right = monitors[0].physicalBounds.right()
        var bottom = monitors[0].physicalBounds.bottom()
        for monitor in monitors
        {
            let bounds = monitor.physicalBounds
            left = Math.min(left, bounds.x)
            top = Math.min(top, bounds.y)
            right = Math.max(right, bounds.right())
            bottom = Math.max(bottom, bounds.bottom())
        }
        return try .open({cast(s32, left), cast(s32, top), cast(s32, right - left),
                          cast(s32, bottom - top), includeCursor})
    }

    private mtd addPart(options: SourceOptions) fail
    {
        let native = Memory.new'NativeSource()
        catch
        {
            #static if #os == Swag.TargetOs.Windows
            {
                native[] = try NativeSource.open(options,
                                                 .sources.count ? .sources[0] : null)
            }
            else do
                native[] = try NativeSource.open(options)
        }
        {
            Memory.delete(native)
            fail Swag.err
        }
        .sources.add(native)
        .pictures.add({})
    }

    // Writes a bottom-up BGRA8 image, returning true when a new selected frame is reported or the composed cursor changes.
    //
    // False means no new selected frame is reported yet, either because the selected image and cursor did not
    // change or because a video readback is still pending. It is not a source failure.
    // By default the previous picture is copied to `target`. Set `copyUnchanged` to false
    // when the caller will reuse its previous encoded picture instead. A reusable target stays
    // untouched on a false return; a new or resized target receives a complete current frame.
    // With `updateChangedOnly` and `copyUnchanged` false,
    // successive grabs into the same unmodified target may update only changed regions after
    // the first complete frame. Replacing or resizing the target causes a complete copy.
    // Windows cursor composition rebuilds the selected area each poll to account for pointer-only changes.
    // The target remains owned by the caller.
    mtd grabInto(target: *Image, copyUnchanged: bool = true,
                 updateChangedOnly: bool = false)->bool fail
    {
        #static if #os == Swag.TargetOs.Linux
        {
            if .sources.count == 1
            {
                let native = .sources[0]
                if native.options.x == .options.x and native.options.y == .options.y and
                   native.options.width == .options.width and native.options.height == .options.height
                {
                    let captured = try native.grabInto(&.composed, preserveOnTimeout: not copyUnchanged)
                    let cached = &.pictures[0]
                    let hasCachedFrame = cached.width == .options.width and
                                         cached.height == .options.height and
                                         cached.pixelFormat == .BGRA8
                    var frameFresh = false
                    if captured
                    {
                        if hasCachedFrame
                        {
                            let detectionStart = Time.monotonicMicroseconds()
                            frameFresh = Memory.compare(cached.pixels.storage(), .composed.pixels.storage(),
                                                        .composed.byteCount) != 0
                            native.metrics.changeDetectionMicroseconds +=
                                Time.monotonicMicroseconds() - detectionStart
                        }
                        else do
                            frameFresh = true
                        if frameFresh
                        {
                            Core.swap(cached, &.composed)
                        }
                        else
                        {
                            native.metrics.unchangedFrames += 1
                        }
                    }
                    let targetReusable = .x11TargetReady and
                                         target.width == .options.width and
                                         target.height == .options.height and
                                         target.pixelFormat == .BGRA8 and
                                         cast(u64, target) == .x11TargetImage and
                                         cast(u64, target.pixels.storage()) == .x11TargetStorage
                    if (frameFresh or hasCachedFrame) and
                       (frameFresh or copyUnchanged or not targetReusable)
                    {
                        if target.width != .options.width or target.height != .options.height or
                           target.pixelFormat != .BGRA8 do
                            target[] = Image.create(.options.width, .options.height, .BGRA8)
                        copyFrameBytes(target.pixels.storage(), cached.pixels.storage(), target.byteCount)
                        .x11TargetImage = cast(u64, target)
                        .x11TargetStorage = cast(u64, target.pixels.storage())
                        .x11TargetReady = true
                    }
                    if frameFresh do
                        .lastFrameCaptureTime = Time.monotonicMicroseconds()
                    return frameFresh
                }
            }
        }
        let first = .composed.width != .options.width or .composed.height != .options.height or
                    .composed.pixelFormat != .BGRA8
        if first
        {
            .composed = Image.create(.options.width, .options.height, .BGRA8)
            Memory.set(.composed.pixels.storage(), 0, .composed.byteCount)
        }
        let incremental = updateChangedOnly and not copyUnchanged and not .options.includeCursor
        var mirroring = false
        #static if #os == Swag.TargetOs.Windows
        {
            mirroring = incremental and .mirrorReady and not first and
                        target.width == .options.width and target.height == .options.height and
                        target.pixelFormat == .BGRA8 and
                        cast(u64, target) == .mirroredImage and
                        cast(u64, target.pixels.storage()) == .mirroredStorage
        }
        .mirrorReady = false
        var fresh = false
        #static if #os == Swag.TargetOs.Windows
        {
            fresh = try .grabWindows(target, mirroring, not copyUnchanged)
        }
        else
        {
            for index in .sources.count
            {
                let nativeSource = .sources[index]
                let x = cast(u64, nativeSource.options.x - .options.x)
                let bottom = cast(u64, .options.height - (nativeSource.options.y - .options.y) - nativeSource.options.height)
                let changed = try nativeSource.grabInto(&.pictures[index], true)
                fresh = changed or fresh
                if not first and not changed do
                    continue
                let part = &.pictures[index]
                let rowBytes = cast(u64, part.width) * 4
                let partComposeStart = Time.monotonicMicroseconds()
                for row in cast(u64, part.height)
                {
                    Memory.copy(.composed.pixels.storage() + (bottom + row) * cast(u64, .composed.rowStride) + x * 4,
                                part.pixels.storage() + row * rowBytes, rowBytes)
                }
                .composeMicroseconds += Time.monotonicMicroseconds() - partComposeStart
            }
        }
        if not fresh and not copyUnchanged and not .options.includeCursor
        {
            .mirrorReady = mirroring
            return false
        }
#static if #os == Swag.TargetOs.Windows
        {
        if .options.includeCursor
        {
            let cursorChanged = try .drawCursor()
            let outputFresh = fresh or cursorChanged
            let targetReusable = .cursorTargetReady and
                                 target.width == .options.width and target.height == .options.height and
                                 target.pixelFormat == .BGRA8 and
                                 cast(u64, target) == .cursorTargetImage and
                                 cast(u64, target.pixels.storage()) == .cursorTargetStorage
            if outputFresh or copyUnchanged or not targetReusable
            {
                if target.width != .options.width or target.height != .options.height or target.pixelFormat != .BGRA8 do
                    target[] = Image.create(.options.width, .options.height, .BGRA8)
                let outputStart = Time.monotonicMicroseconds()
                copyFrameBytes(target.pixels.storage(), cast(const [*] u8, .cursorPixels), target.byteCount)
                .composeMicroseconds += Time.monotonicMicroseconds() - outputStart
                .cursorTargetImage = cast(u64, target)
                .cursorTargetStorage = cast(u64, target.pixels.storage())
                .cursorTargetReady = true
            }
            if outputFresh do
                .lastFrameCaptureTime = Time.monotonicMicroseconds()
            return outputFresh
        }
        }
        if mirroring
        {
            .mirrorReady = true
            if fresh do
                .lastFrameCaptureTime = Time.monotonicMicroseconds()
            return fresh
        }
        if target.width != .options.width or target.height != .options.height or target.pixelFormat != .BGRA8 do
            target[] = Image.create(.options.width, .options.height, .BGRA8)
        let composeStart = Time.monotonicMicroseconds()
        let destination = target.pixels.storage()
        let source = .composed.pixels.storage()
        copyFrameBytes(destination, source, target.byteCount)
        .composeMicroseconds += Time.monotonicMicroseconds() - composeStart
        if incremental
        {
            .mirroredImage = cast(u64, target)
            .mirroredStorage = cast(u64, target.pixels.storage())
            .mirrorReady = true
        }
        if fresh do
            .lastFrameCaptureTime = Time.monotonicMicroseconds()
        return fresh
    }

    // Returns the monotonic capture-completion time of the latest fresh frame, or zero before one is acquired.
    //
    // The value uses the same microsecond clock as [[Core.Time.monotonicMicroseconds]]. It records when
    // `grabInto` received a fresh frame, not the display's presentation time, and remains unchanged when
    // a grab returns false. With cursor composition enabled, cursor-only image changes also update it.
    // A successful reopen resets it to zero; failed attempts preserve it.
    mtd const lastFrameCaptureMicroseconds()->u64 => .lastFrameCaptureTime

    // Returns the latest fresh frame's age in monotonic microseconds; zero can mean no frame or an age under one microsecond.
    // Check lastFrameCaptureMicroseconds() to distinguish those cases.
    // Cursor-only changes count as delivered frames when cursor composition is enabled. A successful reopen clears the age.
    mtd const frameAgeMicroseconds()->u64 => frameAgeAt(Time.monotonicMicroseconds(), .lastFrameCaptureTime)

    // Returns the display presentation time for the latest acquired frame, when the backend reports it.
    // The value shares the monotonic microsecond clock; zero means the backend has no presentation time.
    mtd const lastFramePresentationMicroseconds()->u64 => .lastFramePresentationTime

    // Returns cumulative native and composition timing since this source was opened.
    mtd const metrics()->SourceMetrics
    {
        var result: SourceMetrics
        result.composeMicroseconds = .composeMicroseconds
        result.mirroredPixels = .mirroredPixels
        for source in .sources
        {
            result.composeMicroseconds += source.metrics.composeMicroseconds
            result.acquiredFrames += source.metrics.acquiredFrames
            result.unchangedFrames += source.metrics.unchangedFrames
            result.coalescedUpdates += source.metrics.coalescedUpdates
            result.acquireMicroseconds += source.metrics.acquireMicroseconds
            result.changeDetectionMicroseconds += source.metrics.changeDetectionMicroseconds
            result.maxAcquireMicroseconds = Math.max(result.maxAcquireMicroseconds,
                                                     source.metrics.maxAcquireMicroseconds)
            result.readbackMicroseconds += source.metrics.readbackMicroseconds
            result.maxReadbackMicroseconds = Math.max(result.maxReadbackMicroseconds,
                                                      source.metrics.maxReadbackMicroseconds)
            result.deferredReadbacks += source.metrics.deferredReadbacks
            result.copyMicroseconds += source.metrics.copyMicroseconds
            result.outputMicroseconds += source.metrics.outputMicroseconds
            result.partialFrames += source.metrics.partialFrames
            result.multiRectFrames += source.metrics.multiRectFrames
            result.copiedPixels += source.metrics.copiedPixels
        }
        return result
    }

    // Resets cumulative SourceMetrics counters without reopening the source.
    // The native capture handles, cached frame and last frame capture time are preserved.
    mtd resetMetrics()
    {
        .composeMicroseconds = 0
        .mirroredPixels = 0
        for source in .sources do
            source.metrics = SourceMetrics{}
    }

    // Returns the physical desktop rectangle and cursor policy selected when this source was opened.
    mtd const captureOptions()->SourceOptions => .options

    // Reopens a source after a display change or native access loss.
    mtd reopen() fail
    {
        #static if #os == Swag.TargetOs.Windows
        {
            for index in .sources.count do
                try .sources[index].reopen(index ? .sources[0] : null)
        }
        else
        {
            for source in .sources do
                try source[].reopen()
        }
#static if #os == Swag.TargetOs.Linux
        {
            for index in .pictures.count do
                .pictures[index] = {}
        }
        .lastFrameCaptureTime = 0
        .lastFramePresentationTime = 0
    }

    // Releases the native capture handles and cached frames on the opening thread.
    mtd opDrop()
    {
#static if #os == Swag.TargetOs.Windows
        {
        .closeCursorOverlay()
        }
        for source in .sources do
            Memory.delete(source)
    }
}
