#global if #os == Swag.TargetOs.Linux

using Core, Pixel

// X11 uses an independent XCB connection and MIT-SHM when available.
#[Swag.NoCopy]
struct NativeSource
{
    options: SourceOptions
    capture: X11Capture
    metrics: SourceMetrics
}

impl NativeSource
{
    func open(options: SourceOptions)->NativeSource fail
    {
        var result: #returntype
        result.options = options
        result.capture = try X11Capture.create()
        return result
    }

    mtd grabInto(target: *Image, preserveOnTimeout: bool = false)->bool fail
    {
        discard preserveOnTimeout
        let start = Time.monotonicMicroseconds()
        try .capture.imageInto(target, .options.includeCursor, .options.x, .options.y,
                               .options.width, .options.height)
        let readbackDuration = Time.monotonicMicroseconds() - start
        .metrics.readbackMicroseconds += readbackDuration
        .metrics.maxReadbackMicroseconds = Math.max(.metrics.maxReadbackMicroseconds, readbackDuration)
        .metrics.acquiredFrames += 1
        return true
    }

    mtd reopen() fail
    {
        .capture = try X11Capture.create()
    }
}
