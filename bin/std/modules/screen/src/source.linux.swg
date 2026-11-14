#global if #os == Swag.TargetOs.Linux

using Core, Pixel

// Checks an X11 capture rectangle without opening a display connection.
internal func validateCaptureRect(options: SourceOptions, desktopWidth, desktopHeight: u16) fail
{
    if options.x < 0 or options.y < 0 or
       options.x > 32767 or options.y > 32767 or
       options.width <= 0 or options.height <= 0 do
        fail Errors.BadParameterError{"capture rectangle lies outside the X11 screen"}

    let right  = cast(s64, options.x) + cast(s64, options.width)
    let bottom = cast(s64, options.y) + cast(s64, options.height)
    if right > desktopWidth or bottom > desktopHeight do
        fail Errors.BadParameterError{"capture rectangle lies outside the X11 screen"}
}

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
        try validateCaptureRect(options, result.capture.desktopWidth(), result.capture.desktopHeight())
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
