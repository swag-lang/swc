#global if #os == Swag.TargetOs.Windows

using Core, Audio, Video, Win32

// Owns the selected native sound sources and their separate MP4 tracks while video records.
#[Swag.NoCopy]
struct VideoRecordingAudio
{
    microphoneQueue:    CaptureQueue
    systemQueue:        CaptureQueue
    microphone:         CaptureMicrophone
    system:             CaptureOutputLoopback
    microphonePump:     VideoAudioPump
    systemPump:         VideoAudioPump
    microphoneRecovery: CaptureRecovery
    systemRecovery:     CaptureRecovery
    wantsMicrophone:    bool
    wantsSystem:        bool
    hasMicrophone:      bool
    hasSystem:          bool
    worker:             Threading.Thread
    encoderWorker:      Threading.Thread
    ready:              Sync.Event
    stateMutex:         Swag.Mutex
    encoderMutex:       Swag.Mutex
    workerError:        Swag.Error
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
        var track  = 0'u32
        if microphone
        {
            .wantsMicrophone    = true
            .microphoneQueue    = try CaptureQueue.create(48_000, 1, origin, 10_000_000, slots: 64)
            .microphoneRecovery = try CaptureRecovery.create(&.microphoneQueue, 10_000_000)
            .microphonePump     = try VideoAudioPump.create(session, &.microphoneQueue, track)
            track += 1
        }

        if system
        {
            .wantsSystem    = true
            .systemQueue    = try CaptureQueue.create(48_000, 2, origin, 10_000_000, slots: 64)
            .systemRecovery = try CaptureRecovery.create(&.systemQueue, 10_000_000)
            .systemPump     = try VideoAudioPump.create(session, &.systemQueue, track)
        }

        .ready.init(false)
        try .worker.init(func|audio = me|(thread) { audio.runWorker(thread) })
        expect .worker.start()
        defer #fail .close()
        .ready.wait()
        try .pump()
        try .encoderWorker.init(func|audio = me|(thread) { audio.runEncoder(thread) })
        expect .encoderWorker.start()
    }

    // WASAPI and resampling stay on their opening COM thread. AAC and container I/O cannot
    // delay this producer; a separate worker consumes its bounded queues.
    private mtd runWorker(thread: const *Threading.Thread)
    {
        var signaled = false
        defer if not signaled do
            .ready.signal()
        defer .closeSources()
        catch
        {
            // Audio deadlines must survive a slow picture or a busy interface thread.
            var taskIndex: DWORD
            let taskName = Utf16.toZeroTerminated("Audio")
            let task     = try AvSetMmThreadCharacteristicsW(taskName.buffer, &taskIndex)
            defer discard catch AvRevertMmThreadCharacteristics(task)
            let tick = Time.monotonicMicroseconds() * 10
            if .wantsMicrophone and not .tryOpenMicrophone() do
                try .microphoneRecovery.deviceLost(tick)
            if .wantsSystem and not .tryOpenSystem() do
                try .systemRecovery.deviceLost(tick)
            .ready.signal()
            signaled = true
            while not thread.requestEnd.isRaised()
            {
                try .pumpSources()
                if not .hasMicrophone and not .hasSystem do
                    Threading.Thread.sleep(2'ms)
            }
        }
        {
            .rememberError(Swag.err)
        }
    }

    private mtd runEncoder(thread: const *Threading.Thread)
    {
        catch
        {
            while not thread.requestEnd.isRaised()
            {
                scope
                {
                    .encoderMutex.lock()
                    defer .encoderMutex.unlock()
                    try .drainQueues()
                }

                Threading.Thread.sleep(2'ms)
            }

            .encoderMutex.lock()
            defer .encoderMutex.unlock()
            try .drainQueues()
        }
        {
            .rememberError(Swag.err)
        }
    }

    private mtd rememberError(error: any?)
    {
        .stateMutex.lock()
        defer .stateMutex.unlock()
        if .workerError.isEmpty() do
            .workerError.capture(error)
    }

    private mtd drainQueues() fail
    {
        if .wantsMicrophone
        {
            while try .microphonePump.pump(65_536) != 0 {}
        }

        if .wantsSystem
        {
            while try .systemPump.pump(65_536) != 0 {}
        }
    }

    // UI calls only observe failures; native capture and encoders belong to the worker.
    mtd pump() fail
    {
        .stateMutex.lock()
        defer .stateMutex.unlock()
        try .workerError.raise()
    }

    mtd systemIsActive()->bool
    {
        .stateMutex.lock()
        defer .stateMutex.unlock()
        return .hasSystem
    }

    private mtd setSystemActive(active: bool)
    {
        .stateMutex.lock()
        defer .stateMutex.unlock()
        .hasSystem = active
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

        .setSystemActive(true)
        return true
    }

    private mtd pumpSources() fail
    {
        let tick = Time.monotonicMicroseconds() * 10
        if .hasMicrophone
        {
            discard catch .microphone.pump(5)
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

        if .hasSystem
        {
            discard catch .system.pump(.hasMicrophone ? 0 : 5)
            {
                .system.close()
                .setSystemActive(false)
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
    }

    mtd close()
    {
        if .worker.isValid()
        {
            .worker.safeForceEnd()
            .worker.wait()
        }
        else
        {
            .closeSources()
        }

        if .encoderWorker.isValid()
        {
            .encoderWorker.safeForceEnd()
            .encoderWorker.wait()
        }
        else
        {
            catch .drainQueues() do .rememberError(Swag.err)
        }

        .wantsMicrophone, .wantsSystem = false
    }

    mtd finish() fail
    {
        .close()
        try .workerError.raise()
    }

    private mtd closeSources()
    {
        if .hasMicrophone
        {
            discard catch .microphone.pump()
            .microphone.close()
            .hasMicrophone = false
        }

        if .hasSystem
        {
            discard catch .system.pump()
            .system.close()
            .setSystemActive(false)
        }
    }

    mtd opDrop() => .close()
}
