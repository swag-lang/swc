using Core

// Serializes native opens with ordinary unmount admission. Once admitted, an unmount
// rejects new opens until the dispatcher has drained and its callbacks have returned.
#[Swag.NoCopy]
struct MountActivity
{
    mutex:    Swag.Mutex
    released: Swag.Condition
    handles:  u64
    stopping: bool
}

impl MountActivity
{
    // The native open holds mutex until it has either failed or counted its handle.
    mtd beginStop(force: bool, drainMilliseconds = 0'u32) fail
    {
        .mutex.lock()
        defer .mutex.unlock()
        .stopping = true
        if force do
            return
        let deadline = Time.monotonicMilliseconds() + drainMilliseconds
        while .handles
        {
            let now = Time.monotonicMilliseconds()
            if now >= deadline
            {
                .stopping = false
                fail volumeError(.Busy)
            }

            discard .released.waitFor(&.mutex, cast(u32, deadline - now))
        }
    }

    mtd release()
    {
        .mutex.lock()
        defer .mutex.unlock()
        Swag.assert(.handles != 0)
        .handles -= 1
        if .handles == 0 do
            .released.wakeAll()
    }

    mtd cancelStop()
    {
        .mutex.lock()
        defer .mutex.unlock()
        .stopping = false
    }
}
