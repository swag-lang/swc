#global if #os == Swag.TargetOs.Windows
#global public

using Swag, Core, Core.Errors, Win32

// Captures the Windows system output mix through native WASAPI loopback.
//
// This source reads the default render endpoint, so it includes sound from all applications
// routed to that endpoint. It uses the same 100-nanosecond monotonic clock as
// [[Audio.CaptureMicrophone]] and copies packets into a caller-owned [[Audio.CaptureQueue]].
// The queue must match the endpoint's mono/stereo 44.1/48 kHz shared mix format. A surround
// endpoint or Windows version without event-driven loopback returns an explicit open error.
// Call `pump` and `close` on the opening COM thread. After device loss, close and reopen with
// the same queue when [[Audio.CaptureRecovery]] allows a retry.
#[Swag.NoCopy]
struct CaptureOutputLoopback
{
    private stream: CaptureMicrophone
}

impl CaptureOutputLoopback
{
    // Inspects the default system output mix before constructing its capture queue.
    func describeDefault()->WasapiCaptureFormat fail
    {
        var native = try WasapiCapture.openDefault(.OutputLoopback)
        defer native.close()
        return native.mixFormat()
    }

    // Starts event-driven loopback capture on the current default render endpoint.
    func openDefault(queue: *CaptureQueue)->CaptureOutputLoopback fail
    {
        var result: #returntype
        result.stream = try CaptureMicrophone.openDefaultSource(queue, .OutputLoopback)
        return result
    }

    // Returns the system output mix format read when the endpoint opened.
    mtd const mixFormat()->WasapiCaptureFormat => .stream.mixFormat()

    // Waits up to `timeoutMs` for output packets and copies all available data to the queue.
    mtd pump(timeoutMs: u32 = 0)->u32 fail => try .stream.pump(timeoutMs)

    // Stops loopback and releases the endpoint, event, and COM apartment resources.
    mtd close() => .stream.close()
}
