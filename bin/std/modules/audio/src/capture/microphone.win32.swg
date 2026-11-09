#global if #os == Swag.TargetOs.Windows
#global public

using Swag, Core, Core.Errors, Win32

// Pumps the default Windows microphone into a timestamped PCM16 capture queue.
//
// This adapter uses native shared-mode WASAPI with an event handle and no codec library. The
// queue must use mono/stereo at 44.1/48 kHz and a 10 MHz timestamp clock. Source rates from
// 8-192 kHz are resampled and corrected for measured device-clock drift. Call `pump` and `close`
// on the same COM thread that opened the microphone.
// If a device failure is reported, mark the queue lost, close this adapter, and reopen the
// default endpoint with the same queue after [[Audio.CaptureRecovery]] permits a retry.
#[Swag.NoCopy]
struct CaptureMicrophone
{
    private
    {
        native:                WasapiCapture
        feeder:                CaptureResampledFeeder
        late queue:            *CaptureQueue
        format:                WasapiCaptureFormat
        source:                WasapiCaptureSource
        pendingDiscontinuity:  bool
        lastSourceEndTick:     u64
    }
}

impl CaptureMicrophone
{
    // Inspects the current default endpoint's mix format before constructing a capture queue.
    //
    // This opens the endpoint briefly and returns its sample rate and channel count. The output
    // queue may use a different rate and mono/stereo channel layout.
    func describeDefault()->WasapiCaptureFormat fail
    {
        var native = try WasapiCapture.openDefault()
        defer native.close()
        return native.mixFormat()
    }

    // Opens the current default input endpoint and starts event-driven capture.
    //
    // Use [[Win32.wasapiCaptureNow100ns]] for the queue's origin tick when picture and sound
    // should share a monotonic start. The queue outputs 44.1/48 kHz mono/stereo; 8-192 kHz
    // native PCM16 or float32 is converted to that rate on the producer's COM thread.
    func openDefault(queue: *CaptureQueue)->CaptureMicrophone fail
        => try openDefaultSource(queue, .Microphone)

    // Opens either Windows source through the same queue conversion and packet lifecycle.
    internal func openDefaultSource(queue: *CaptureQueue, source: WasapiCaptureSource)->CaptureMicrophone fail
    {
        if queue.clockFrequencyHz() != 10_000_000 do
            fail BadParameterError{"WASAPI capture queue must use 100-nanosecond timestamps"}
        var result: #returntype
        result.native = try WasapiCapture.openDefault(source)
        defer #fail result.native.close()
        result.format = result.native.mixFormat()
        result.queue = queue
        result.source = source
        result.feeder = try CaptureResampledFeeder.create(queue, result.format.sampleRate,
                                                          result.format.channels)
        return result
    }

    // Returns the microphone's PCM source rate and mono/stereo channel count.
    mtd const mixFormat()->WasapiCaptureFormat => .format

    // Returns whether the source clock has been measured against monotonic QPC time.
    mtd const clockEstimateIsReady()->bool => .feeder.clockEstimateIsReady()

    // Returns the last measured source-clock offset in parts per million.
    mtd const inputClockDriftPpm()->s32 => .feeder.inputClockDriftPpm()

    // Waits for a capture event and drains every currently available source packet.
    //
    // Returns the number of packets, including those skipped for an invalid hardware timestamp.
    // `timeoutMs` can be zero for polling. Each packet is released before the next is borrowed.
    mtd pump(timeoutMs: u32 = 0)->u32 fail
    {
        if not try .native.wait(timeoutMs)
        {
            try .advanceIdleLoopback()
            return 0
        }
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
                try .feeder.pushSilence(packet.frames, packet.timestamp100ns,
                                        packet.devicePosition, discontinuity)
            else
            {
                if .format.sampleFormat == .Pcm16
                {
                    let pcm = cast(const [*] s16, unwrap packet.data)
                    try .feeder.pushPcm16(Swag.makeSlice(pcm, cast(u64, packet.frames) * .format.channels),
                                          packet.timestamp100ns, packet.devicePosition, discontinuity)
                }
                else
                {
                    let pcm = cast(const [*] f32, unwrap packet.data)
                    try .feeder.pushFloat32(Swag.makeSlice(pcm, cast(u64, packet.frames) * .format.channels),
                                            packet.timestamp100ns, packet.devicePosition, discontinuity)
                }
            }
            .pendingDiscontinuity = false
            let packetTicks = (cast(u64, packet.frames) * 10_000_000 + .format.sampleRate / 2) /
                              .format.sampleRate
            if packetTicks > Swag.U64.Max - packet.timestamp100ns do
                fail OverflowError{"WASAPI capture packet end timestamp overflows"}
            .lastSourceEndTick = packet.timestamp100ns + packetTicks
            try .native.releasePacket()
        }
        try .advanceIdleLoopback()
        return count
    }

    // Stops capture and releases native endpoint, event, and COM apartment resources.
    mtd close()
    {
        discard catch .feeder.finish()
        .native.close()
    }
}

private impl CaptureMicrophone
{
    mtd advanceIdleLoopback() fail
    {
        if .source != .OutputLoopback do
            return
        // Leave 250 ms for packets already mixed by the render endpoint to arrive before
        // committing the otherwise silent interval to a live AAC track.
        const SafeLag100ns = 2_500_000'u64
        let now = try wasapiCaptureNow100ns()
        if now <= SafeLag100ns or now - SafeLag100ns <= .lastSourceEndTick do
            return
        try .feeder.suspendForIdle()
        discard try .queue.markSilentUntil(now - SafeLag100ns)
    }
}
