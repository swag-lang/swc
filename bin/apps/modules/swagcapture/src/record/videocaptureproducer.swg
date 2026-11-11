using Core, Video

// Reads desktop frames on one native thread, independently of interface rendering. The
// encoder has its own bounded worker; this producer owns the screen source and frame pacer.
#[Swag.NoCopy]
struct VideoCaptureProducer
{
    late session: *VideoCaptureSession
    rate:         u32
    worker:       Threading.Thread
    positionMutex: Swag.Mutex
    x, y:         s32
    paused:       u32
    ready:        u32
    failed:       u32
    missedSlots:  u64
    error:        Swag.Error
}

impl VideoCaptureProducer
{
    mtd start(session: *VideoCaptureSession, rate: u32) fail
    {
        .session = session
        .rate = rate
        .x = session.source.x
        .y = session.source.y
        try .worker.init(func|producer = me|(thread) { producer.run(thread) })
        try .worker.start()
    }

    private mtd run(thread: const *Threading.Thread)
    {
        var waiter: CaptureFrameWaiter
        waiter.open()
        catch
        {
            while not thread.requestEnd.isRaised()
            {
                if Atomic.get(&.paused)
                {
                    Threading.Thread.sleep(1'ms)
                    continue
                }

                .positionMutex.lock()
                .session.source.x = .x
                .session.source.y = .y
                .positionMutex.unlock()

                let fresh = try .session.captureAt(Time.monotonicMicroseconds())
                Atomic.exchange(&.missedSlots, .session.missedFrameSlotCount())
                if .session.hasCaptureOrigin() do
                    Atomic.exchange(&.ready, 1)

                if not fresh
                {
                    let nextTick = .session.captureOriginTick() +
                                   .session.frameCount() * 1_000_000 / .rate
                    waiter.waitUntil(nextTick)
                }
            }
        }
        {
            .error.capture(Swag.err)
            Atomic.exchange(&.failed, 1)
        }
    }

    mtd setPosition(x, y: s32)
    {
        .positionMutex.lock()
        .x = x
        .y = y
        .positionMutex.unlock()
    }

    mtd setPaused(paused: bool)
    {
        discard Atomic.exchange(&.paused, paused ? 1'u32 : 0'u32)
    }
    mtd const hasOrigin()->bool => Atomic.get(&.ready) != 0
    mtd const hasFailed()->bool => Atomic.get(&.failed) != 0
    mtd const missedFrameSlotCount()->u64 => Atomic.get(&.missedSlots)

    mtd close()
    {
        if .worker.isValid()
        {
            .worker.safeForceEnd()
            .worker.wait()
        }
    }

    mtd raiseError() fail => try .error.raise()
    mtd opDrop() => .close()
}
