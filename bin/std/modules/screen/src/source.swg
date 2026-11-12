#global public

using Core, Core.Errors, Pixel

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
    public includeCursor: bool    // Includes the pointer when the native source supports it.
}

// Cumulative acquisition costs for one [[Screen.Source]], in microseconds.
struct SourceMetrics
{
    public acquiredFrames:       u64 // Desktop frames returned by the native source.
    public unchangedFrames:      u64 // Polls with no newer desktop pixels.
    public acquireMicroseconds:  u64 // Time waiting for a native frame.
    public readbackMicroseconds: u64 // Time until native pixels become CPU-readable.
    public copyMicroseconds:     u64 // Time copying native pixels into owned storage.
    public outputMicroseconds:   u64 // Native cache-output time, zero for current backends.
    public composeMicroseconds:  u64 // Time joining outputs and copying pixels into the caller's image.
    public partialFrames:        u64 // Frames read through a region smaller than the selected output.
    public copiedPixels:         u64 // Pixels copied from mapped native storage, including full frames.
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
        mirroredImage:        u64
        mirroredStorage:      u64
        mirrorReady:          bool
    }
}

impl Source
{
    // Opens a native source for one physical desktop area.
    //
    // Rejects invalid dimensions, unavailable displays and capture permission failures.
    func open(options: SourceOptions)->Source fail
    {
        if options.width <= 0 or options.height <= 0 or options.width > 0x7FFFFFFF's32 / 4 do
            fail BadParameterError{"screen source needs positive dimensions"}
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

    private mtd addPart(options: SourceOptions) fail
    {
        let native = Memory.new'NativeSource()
        catch
        {
            native[] = try NativeSource.open(options)
        }
        {
            Memory.delete(native)
            fail Swag.err
        }
        .sources.add(native)
        .pictures.add({})
    }

    // Writes a bottom-up BGRA8 image, returning true when a new desktop frame was acquired.
    //
    // False means the desktop pixels did not change; it is not a source failure.
    // By default the previous picture is copied to `target`. Set `copyUnchanged` to false
    // when the caller will reuse its previous encoded picture instead; on a false return,
    // `target` is then left untouched. With `updateChangedOnly` and `copyUnchanged` false,
    // successive grabs into the same unmodified target may update only changed regions after
    // the first complete frame. Replacing or resizing the target causes a complete copy.
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
                   native.options.width == .options.width and native.options.height == .options.height do
                    return try native.grabInto(target, preserveOnTimeout: not copyUnchanged)
            }
        }
        let first = .composed.width != .options.width or .composed.height != .options.height or
                    .composed.pixelFormat != .BGRA8
        if first
        {
            .composed = Image.create(.options.width, .options.height, .BGRA8)
            Memory.set(.composed.pixels.storage(), 0, .composed.byteCount)
        }
        let incremental = updateChangedOnly and not copyUnchanged
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
            fresh = try .grabWindows(target, mirroring)
        }
        else
        {
            for index in .sources.count
            {
                let source = .sources[index]
                let x = cast(u64, source.options.x - .options.x)
                let bottom = cast(u64, .options.height - (source.options.y - .options.y) - source.options.height)
                let changed = try source.grabInto(&.pictures[index], true)
                fresh = changed or fresh
                if not first and not changed do
                    continue
                let part = &.pictures[index]
                let rowBytes = cast(u64, part.width) * 4
                let composeStart = Time.monotonicMicroseconds()
                for row in cast(u64, part.height)
                {
                    Memory.copy(.composed.pixels.storage() + (bottom + row) * cast(u64, .composed.rowStride) + x * 4,
                                part.pixels.storage() + row * rowBytes, rowBytes)
                }
                .composeMicroseconds += Time.monotonicMicroseconds() - composeStart
            }
        }
        if not fresh and not copyUnchanged
        {
            .mirrorReady = mirroring
            return false
        }
        if mirroring
        {
            .mirrorReady = true
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
        return fresh
    }

    // Returns cumulative native and composition timing since this source was opened.
    mtd const metrics()->SourceMetrics
    {
        var result: SourceMetrics
        result.composeMicroseconds = .composeMicroseconds
        for source in .sources
        {
            result.acquiredFrames += source.metrics.acquiredFrames
            result.unchangedFrames += source.metrics.unchangedFrames
            result.acquireMicroseconds += source.metrics.acquireMicroseconds
            result.readbackMicroseconds += source.metrics.readbackMicroseconds
            result.copyMicroseconds += source.metrics.copyMicroseconds
            result.outputMicroseconds += source.metrics.outputMicroseconds
            result.partialFrames += source.metrics.partialFrames
            result.copiedPixels += source.metrics.copiedPixels
        }
        return result
    }

    // Reopens a source after a display change or native access loss.
    mtd reopen() fail
    {
        for source in .sources do
            try source[].reopen()
    }

    // Releases the native capture handles and cached frames on the opening thread.
    mtd opDrop()
    {
        for source in .sources do
            Memory.delete(source)
    }
}
