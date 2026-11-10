#global if #os == Swag.TargetOs.Windows

using Core, Audio, Video

// Owns the selected native sound sources and their separate MP4 tracks while video records.
#[Swag.NoCopy]
struct VideoRecordingAudio
{
    microphoneQueue: CaptureQueue
    systemQueue:     CaptureQueue
    microphone:      CaptureMicrophone
    system:          CaptureOutputLoopback
    microphonePump:  VideoAudioPump
    systemPump:      VideoAudioPump
    microphoneRecovery: CaptureRecovery
    systemRecovery:     CaptureRecovery
    wantsMicrophone: bool
    wantsSystem:     bool
    hasMicrophone:   bool
    hasSystem:       bool
}

impl VideoRecordingAudio
{
    func configs(microphone, system: bool)->Array'Mp4.SoftwareAudioConfig
    {
        var result: #returntype
        if microphone do
            result.add(Mp4.SoftwareAudioConfig{48_000, 1, .Voice})
        if system do
            result.add(Mp4.SoftwareAudioConfig{48_000, 2, .Full})
        return result
    }

    mtd start(session: *VideoCaptureSession, microphone, system: bool) fail
    {
        let origin = try session.captureOrigin100ns()
        var track = 0'u32
        defer #fail .close()
        if microphone
        {
            .wantsMicrophone = true
            .microphoneQueue = try CaptureQueue.create(48_000, 1, origin, 10_000_000)
            .microphoneRecovery = try CaptureRecovery.create(&.microphoneQueue, 10_000_000)
            .microphonePump = try VideoAudioPump.create(session, &.microphoneQueue, track)
            if not .tryOpenMicrophone() do
                try .microphoneRecovery.deviceLost(origin)
            track += 1
        }
        if system
        {
            .wantsSystem = true
            .systemQueue = try CaptureQueue.create(48_000, 2, origin, 10_000_000)
            .systemRecovery = try CaptureRecovery.create(&.systemQueue, 10_000_000)
            .systemPump = try VideoAudioPump.create(session, &.systemQueue, track)
            if not .tryOpenSystem() do
                try .systemRecovery.deviceLost(origin)
        }
    }

    private mtd tryOpenMicrophone()->bool
    {
        catch { .microphone = try CaptureMicrophone.openDefault(&.microphoneQueue) }
        {
            return false
        }
        .hasMicrophone = true
        return true
    }

    private mtd tryOpenSystem()->bool
    {
        catch { .system = try CaptureOutputLoopback.openDefault(&.systemQueue) }
        {
            return false
        }
        .hasSystem = true
        return true
    }

    mtd pump() fail
    {
        let tick = Time.monotonicMicroseconds() * 10
        if .hasMicrophone
        {
            discard catch .microphone.pump()
            {
                .microphone.close()
                .hasMicrophone = false
                try .microphoneRecovery.deviceLost(tick)
            }
        }
        elif .wantsMicrophone
        {
            try .microphoneRecovery.deviceLost(tick)
            if .microphoneRecovery.retryDue(tick)
            {
                if .tryOpenMicrophone() do
                    try .microphoneRecovery.deviceRestored(tick)
                else do
                    try .microphoneRecovery.retryFailed(tick)
            }
        }
        if .wantsMicrophone do
            discard try .microphonePump.pump()
        if .hasSystem
        {
            discard catch .system.pump()
            {
                .system.close()
                .hasSystem = false
                try .systemRecovery.deviceLost(tick)
            }
        }
        elif .wantsSystem
        {
            try .systemRecovery.deviceLost(tick)
            if .systemRecovery.retryDue(tick)
            {
                if .tryOpenSystem() do
                    try .systemRecovery.deviceRestored(tick)
                else do
                    try .systemRecovery.retryFailed(tick)
            }
        }
        if .wantsSystem do
            discard try .systemPump.pump()
    }

    mtd close()
    {
        if .hasMicrophone
        {
            discard catch .microphone.pump()
            .microphone.close()
            .hasMicrophone = false
        }
        // The live pump is deliberately bounded. At stop, drain every retained block, including
        // the resampler tail, before finalizing AAC; one live budget could leave audible data out.
        if .wantsMicrophone
        {
            while (catch .microphonePump.pump(65_536)) != 0 {}
        }
        .wantsMicrophone = false
        if .hasSystem
        {
            discard catch .system.pump()
            .system.close()
            .hasSystem = false
        }
        if .wantsSystem
        {
            while (catch .systemPump.pump(65_536)) != 0 {}
        }
        .wantsSystem = false
    }

    mtd opDrop() => .close()
}
