#global if #os == Swag.TargetOs.Windows
#global public

using Swag, Core, Core.Errors, Win32

// Pumps the default Windows microphone into a timestamped PCM16 capture queue.
//
// This adapter uses native shared-mode WASAPI with an event handle and no codec library. The
// queue must be configured for the endpoint's 44.1/48 kHz mono/stereo mix format and a 10 MHz
// timestamp clock. Call `pump` and `close` on the same COM thread that opened the microphone.
// If a device failure is reported, mark the queue lost, close this adapter, and reopen the
// default endpoint with the same queue after [[Audio.CaptureRecovery]] permits a retry.
#[Swag.NoCopy]
struct CaptureMicrophone
{
    private
    {
        native:                WasapiCapture
        feeder:                CapturePcmFeeder
        late queue:            *CaptureQueue
        format:                WasapiCaptureFormat
        pendingDiscontinuity:  bool
    }
}

impl CaptureMicrophone
{
    // Inspects the current default endpoint's mix format before constructing a capture queue.
    //
    // This opens the endpoint briefly and returns the sample rate and channel count expected by
    // `openDefault`. A device change between inspection and opening is reported as a mismatch.
    func describeDefault()->WasapiCaptureFormat fail
    {
        var native = try WasapiCapture.openDefault()
        defer native.close()
        return native.mixFormat()
    }

    // Opens the current default input endpoint and starts event-driven capture.
    //
    // Use [[Win32.wasapiCaptureNow100ns]] for the queue's origin tick when picture and sound
    // should share a monotonic start. Unsupported rates, channel counts, and mix encodings fail.
    func openDefault(queue: *CaptureQueue)->CaptureMicrophone fail
    {
        if queue.clockFrequencyHz() != 10_000_000 do
            fail BadParameterError{"WASAPI capture queue must use 100-nanosecond timestamps"}
        var result: #returntype
        result.native = try WasapiCapture.openDefault()
        defer #fail result.native.close()
        result.format = result.native.mixFormat()
        if queue.sampleRateHz() != result.format.sampleRate or
           queue.channelCount() != result.format.channels do
            fail BadParameterError{"capture queue must match the microphone shared mix format"}
        result.queue = queue
        result.feeder = CapturePcmFeeder.create(queue)
        return result
    }

    // Returns the microphone's PCM source rate and mono/stereo channel count.
    mtd const mixFormat()->WasapiCaptureFormat => .format

    // Waits for a capture event and drains every currently available source packet.
    //
    // Returns the number of packets, including those skipped for an invalid hardware timestamp.
    // `timeoutMs` can be zero for polling. Each packet is released before the next is borrowed.
    mtd pump(timeoutMs: u32 = 0)->u32 fail
    {
        if not try .native.wait(timeoutMs) do
            return 0
        var count = 0'u32
        var packet: WasapiCapturePacket
        while try .native.nextPacket(&packet)
        {
            defer #fail discard catch .native.releasePacket()
            count += 1
            if packet.flags & AUDCLNT_BUFFERFLAGS_TIMESTAMP_ERROR
            {
                .pendingDiscontinuity = true
                try .native.releasePacket()
                continue
            }

            let discontinuity = .pendingDiscontinuity or
                                (packet.flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) != 0
            if packet.flags & AUDCLNT_BUFFERFLAGS_SILENT do
                try .feeder.pushSilence(packet.frames, packet.timestamp100ns, discontinuity)
            else
            {
                if .format.sampleFormat == .Pcm16
                {
                    let pcm = cast(const [*] s16, unwrap packet.data)
                    try .feeder.pushPcm16(Swag.makeSlice(pcm, cast(u64, packet.frames) * .format.channels),
                                          packet.timestamp100ns, discontinuity)
                }
                else
                {
                    let pcm = cast(const [*] f32, unwrap packet.data)
                    try .feeder.pushFloat32(Swag.makeSlice(pcm, cast(u64, packet.frames) * .format.channels),
                                            packet.timestamp100ns, discontinuity)
                }
            }
            .pendingDiscontinuity = false
            try .native.releasePacket()
        }
        return count
    }

    // Stops capture and releases native endpoint, event, and COM apartment resources.
    mtd close() => .native.close()
}
