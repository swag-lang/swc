#global if #os == Swag.TargetOs.Linux
#global namespace Sync

using Core.Errors, Math, Time

private struct EventState
{
    mutex:      Linux.pthread_mutex_t
    changed:    Linux.pthread_cond_t
    manual:     bool
    signaled:   bool
    waiters:    u32
    permits:    u32
    generation: u64
}

internal func raiseEventFailure(errorCode: u32) fail
{
    fail Swag.SystemError{"event operation failed", errorID: errorCode}
}

private func eventStatus(error: s32)->EventStatus => {succeeded: error == 0, errorCode: cast #bit (u32, error)}

private func createEventState(manual, initState: bool)->*EventState fail
{
    let allocation = Linux.calloc(1, #sizeof(EventState))
    if not allocation do
        fail Swag.SystemError{"cannot allocate event state", errorID: Linux.ENOMEM}
    let state = cast(*EventState, allocation)
    defer #fail Linux.free(state)
    try eventStatus(Linux.pthread_mutex_init(&state.mutex, null)).raise()
    defer #fail discard Linux.pthread_mutex_destroy(&state.mutex)
    var condAttributes: Linux.pthread_condattr_t
    try eventStatus(Linux.pthread_condattr_init(&condAttributes)).raise()
    defer #fail discard Linux.pthread_condattr_destroy(&condAttributes)
    try eventStatus(Linux.pthread_condattr_setclock(&condAttributes, Linux.CLOCK_MONOTONIC)).raise()
    try eventStatus(Linux.pthread_cond_init(&state.changed, cast(const *void, &condAttributes))).raise()
    state.manual   = manual
    state.signaled = initState
    return state
}

// Owns an unnamed event that threads in this process signal and wait on.
//
// An auto-reset event releases one waiter and consumes its signaled state. Repeated signals
// coalesce while it is signaled. A manual-reset event releases all waiters and stays signaled
// until reset. The owner must outlive all operations; join waiters before release or drop.
// Linux named interprocess events are not provided by this type yet.
#[Swag.NoCopy, Swag.Opaque]
public struct Event { private state: *EventState? }

public impl Event
{
    // Releases the event when its owner leaves scope; no thread may still use it.
    mtd opDrop() { .release() }

    // Reports whether the event owns initialized synchronization state.
    mtd isValid()->bool => .state != null

    // Creates an unnamed auto-reset event that starts unsignaled.
    func create()->Event
    {
        var result: #returntype
        result.init()
        return result
    }

    // Creates an unnamed event in this value, which must not own one yet.
    //
    // `manual` selects a manual-reset event; `initState` starts it signaled. Allocation or
    // native initialization failure panics. Initialization must finish before sharing the event.
    mtd init(manual = false, initState = false)
    {
        Swag.assert(not .isValid())
        .state = expect createEventState(manual, initState)
    }

    // Releases the native state; repeated calls do nothing.
    //
    // All waiters must have returned and no thread may access the event during this operation.
    mtd release()
    {
        if not .state do
            return
        let state: *EventState = .state
        expect eventStatus(Linux.pthread_cond_destroy(&state.changed)).raise()
        expect eventStatus(Linux.pthread_mutex_destroy(&state.mutex)).raise()
        Linux.free(state)
        .state = null
    }

    // Sets the event to the signaled state, releasing one waiter or all manual-reset waiters.
    mtd signal() { expect .signalStatus().raise() }

    // Returns the event to the unsignaled state.
    mtd reset() { expect .resetStatus().raise() }

    // Blocks until a signal is available; an auto-reset wait consumes that signal.
    mtd wait() { expect .waitStatus().raise() }

    // Waits for a signal for up to `timeout`, returning false when it expires.
    //
    // The timeout is measured with the monotonic clock and rounded up to whole milliseconds.
    // It must be finite, nonnegative, and representable as a u64 millisecond count. A successful
    // auto-reset wait consumes the signal. Native synchronization failures are raised.
    mtd waitFor(timeout: Time.Duration)->bool fail
    {
        if not Math.isFinite(timeout.seconds) or
           timeout.seconds < 0 or
           timeout.seconds >= 18_446_744_073_709_550.0 do
            fail Errors.BadParameterError{"event timeout is outside the supported range"}

        let timeoutMilliseconds = timeout.millisecondsCeiling()
        var deadline: Linux.timespec
        if Linux.clock_gettime(Linux.CLOCK_MONOTONIC, &deadline) != 0 do
            try Errors.failLinuxError(Linux.errno())
        deadline.tv_sec  += cast(s64, timeoutMilliseconds / 1000)
        deadline.tv_nsec += cast(s64, timeoutMilliseconds % 1000) * 1_000_000
        if deadline.tv_nsec >= 1_000_000_000
        {
            deadline.tv_nsec -= 1_000_000_000
            deadline.tv_sec  += 1
        }

        if not .state do
            try eventStatus(Linux.EINVAL).raise()
        let state: *EventState = unwrap .state
        let locked = Linux.pthread_mutex_lock(&state.mutex)
        if locked != 0 do
            try eventStatus(locked).raise()

        if state.signaled or not state.manual and state.permits != 0
        {
            if not state.manual
            {
                if state.permits != 0 do
                    state.permits -= #wrap 1
                else do
                    state.signaled = false
            }

            let unlocked = Linux.pthread_mutex_unlock(&state.mutex)
            if unlocked != 0 do
                try eventStatus(unlocked).raise()
            return true
        }

        if not timeoutMilliseconds
        {
            let unlocked = Linux.pthread_mutex_unlock(&state.mutex)
            if unlocked != 0 do
                try eventStatus(unlocked).raise()
            return false
        }

        let generation = state.generation
        state.waiters += #wrap 1
        var waited: s32
        while state.manual ? not state.signaled and state.generation == generation : state.permits == 0 and not state.signaled
        {
            waited = Linux.pthread_cond_timedwait(&state.changed, &state.mutex, &deadline)
            if waited != 0 do
                break
        }

        if waited != 0 and waited != Linux.ETIMEDOUT
        {
            state.waiters -= #wrap 1
            let unlocked = Linux.pthread_mutex_unlock(&state.mutex)
            if unlocked != 0 do
                try eventStatus(unlocked).raise()
            try eventStatus(waited).raise()
        }

        let signaled = state.manual ? state.signaled or state.generation != generation : state.permits != 0 or state.signaled
        if signaled and not state.manual
        {
            if state.permits != 0 do
                state.permits -= #wrap 1
            else do
                state.signaled = false
        }

        state.waiters -= #wrap 1
        let unlocked = Linux.pthread_mutex_unlock(&state.mutex)

        if unlocked != 0 do
            try eventStatus(unlocked).raise()
        return signaled
    }

    // Signals without allocating error storage or invoking error hooks.
    //
    // An uninitialized event returns a failed status with EINVAL. Report it later through
    // [[Core.Sync.EventStatus.raise]], after releasing any borrowed state.
    mtd signalStatus()->EventStatus
    {
        if not .state do
            return eventStatus(Linux.EINVAL)
        let state: *EventState = .state
        let locked = Linux.pthread_mutex_lock(&state.mutex)
        if locked != 0 do
            return eventStatus(locked)

        // Reserve signals for waiters already blocked, so a later reset cannot revoke them.
        if state.manual
        {
            state.signaled   = true
            state.generation += #wrap 1
        }
        elif state.waiters > state.permits
        {
            state.permits += #wrap 1
        }
        else
        {
            state.signaled = true
        }

        let notified = state.manual ? Linux.pthread_cond_broadcast(&state.changed) : Linux.pthread_cond_signal(&state.changed)
        let unlocked = Linux.pthread_mutex_unlock(&state.mutex)
        return eventStatus(notified != 0 ? notified : unlocked)
    }

    // Resets without allocating error storage or invoking error hooks, even for an invalid event.
    mtd resetStatus()->EventStatus
    {
        if not .state do
            return eventStatus(Linux.EINVAL)
        let state: *EventState = .state
        let locked = Linux.pthread_mutex_lock(&state.mutex)
        if locked != 0 do
            return eventStatus(locked)
        state.signaled = false
        return eventStatus(Linux.pthread_mutex_unlock(&state.mutex))
    }

    // Waits for a signal and returns an outcome for deferred failure handling.
    //
    // A successful wait observes work published before signaling. This does not dispatch
    // messages or callbacks. Invalid events fail without allocating or invoking error hooks.
    mtd waitStatus()->EventStatus
    {
        if not .state do
            return eventStatus(Linux.EINVAL)
        let state: *EventState = .state
        let locked = Linux.pthread_mutex_lock(&state.mutex)
        if locked != 0 do
            return eventStatus(locked)
        if state.signaled
        {
            if not state.manual do
                state.signaled = false
            return eventStatus(Linux.pthread_mutex_unlock(&state.mutex))
        }

        let generation = state.generation
        state.waiters += #wrap 1
        var waited: s32
        while state.manual ? not state.signaled and state.generation == generation : state.permits == 0 and not state.signaled
        {
            waited = Linux.pthread_cond_wait(&state.changed, &state.mutex)
            if waited != 0 do
                break
        }

        state.waiters -= #wrap 1
        if waited == 0 and not state.manual
        {
            if state.permits != 0 do
                state.permits -= #wrap 1
            else do
                state.signaled = false
        }

        let unlocked = Linux.pthread_mutex_unlock(&state.mutex)
        return eventStatus(waited != 0 ? waited : unlocked)
    }
}
