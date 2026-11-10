using Core, Core.Errors, Pixel, Video

struct VideoCaptureFrame
{
    picture:  Image
    slot:     FrameSlot
    repeated: bool
}

// A bounded handoff lets screen readback overlap encoding without retaining a growing movie.
// The interface produces slots; this worker alone owns the video encoder until it is joined.
#[Swag.NoCopy]
struct VideoCaptureEncoder
{
    late recording:     *Mp4.SoftwareRecording
    worker:             Threading.Thread
    mutex:              Swag.Mutex
    available:          Sync.Event
    room:               Sync.Event
    error:              Swag.Error
    frames:             [2] VideoCaptureFrame
    head, count:        u32
    busy:               bool
    enabled:            bool
    encodeMicroseconds: u64
    repeatMicroseconds: u64
}

impl VideoCaptureEncoder
{
    mtd start(recording: *Mp4.SoftwareRecording) fail
    {
        .recording = recording
        .available.init(false)
        .room.init(false)
        try .worker.init(func|encoder = me|(thread) { encoder.run(thread) })
        expect .worker.start()
        .enabled = true
    }

    // Swap reusable storage rather than copying an entire desktop picture into the queue.
    mtd add(picture: *Image, slot: FrameSlot, repeated: bool) fail
    {
        while true
        {
            scope
            {
                .mutex.lock()
                defer .mutex.unlock()
                try .error.raise()
                if not .worker.isValid() do
                    fail BadParameterError{"video capture encoder has stopped"}
                if .count < .frames.count
                {
                    let frame = &.frames[(.head + .count) % .frames.count]
                    frame.slot     = slot
                    frame.repeated = repeated
                    if not repeated do
                        Core.swap(picture, &frame.picture)
                    .count += 1
                    .available.signal()
                    return
                }
            }

            .room.wait()
        }
    }

    private mtd run(thread: const *Threading.Thread)
    {
        var frame: VideoCaptureFrame
        catch
        {
            while true
            {
                var received = false
                scope
                {
                    .mutex.lock()
                    defer .mutex.unlock()
                    if .count
                    {
                        let queued = &.frames[.head]
                        frame.slot     = queued.slot
                        frame.repeated = queued.repeated
                        if not frame.repeated do
                            Core.swap(&frame.picture, &queued.picture)
                        .head    = (.head + 1) % .frames.count
                        .count   -= 1
                        .busy    = true
                        received = true
                    }
                    elif thread.requestEnd.isRaised()
                    {
                        return
                    }
                }

                if not received
                {
                    .available.wait()
                    continue
                }

                .room.signal()
                let start = Time.monotonicMicroseconds()
                if frame.repeated
                {
                    try .recording.repeatLastFrame(frame.slot)
                    Atomic.add(&.repeatMicroseconds, Time.monotonicMicroseconds() - start)
                }
                else
                {
                    try .recording.addFrame(&frame.picture, frame.slot)
                    Atomic.add(&.encodeMicroseconds, Time.monotonicMicroseconds() - start)
                }

                .mutex.lock()
                .busy = false
                .mutex.unlock()
                .room.signal()
            }
        }
        {
            .mutex.lock()
            .error.capture(Swag.err)
            .busy = false
            .mutex.unlock()
            .room.signal()
        }
    }

    mtd waitIdle() fail
    {
        if not .enabled do
            return
        while true
        {
            scope
            {
                .mutex.lock()
                defer .mutex.unlock()
                try .error.raise()
                if not .count and not .busy do
                    return
            }

            .room.wait()
        }
    }

    mtd close()
    {
        if .worker.isValid()
        {
            .worker.safeForceEnd()
            .available.signal()
            .worker.wait()
        }
    }

    mtd finish() fail
    {
        .close()
        try .error.raise()
    }

    mtd opDrop() => .close()
}
