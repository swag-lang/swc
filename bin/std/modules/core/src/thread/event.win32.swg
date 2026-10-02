#global if WINDOWS
#global public
#global namespace Sync

using Win32

// Owns an operating-system event that threads signal and wait on.
//
// An auto-reset event releases one waiter per signal and returns to the unsignaled state; a
// manual-reset event stays signaled, releasing every waiter, until [[Core.Sync.Event.reset]].
#[Swag.NoCopy]
struct Event
{
    public handle: HANDLE?     // Native event handle, or null when the event is not initialized.
}

impl Event
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .release()
    }

    // Returns whether the event owns a native handle.
    mtd isValid()->bool => .handle != null

    // Creates an unnamed auto-reset event that starts unsignaled.
    func create()->Event
    {
        var result: retval
        result.init()
        return result
    }

    // Creates an unnamed event in this value, which must not own one yet.
    //
    // `manual` selects a manual-reset event, and `initState` starts it signaled. A failure of
    // the operating system panics.
    mtd init(manual, initState = false)
    {
        Swag.assert(.handle == null)
        .handle = expect CreateEventA(null, manual ? TRUE : FALSE, initState ? TRUE : FALSE, null)
    }

    // Creates or opens a named event shared by processes in the current login session.
    //
    // The event must be invalid on entry. `name` is borrowed only during this call, is
    // case-sensitive, and must be nonempty without zero bytes or backslashes. On Windows,
    // the name is resolved in the local session namespace. An existing event retains its
    // reset mode and signaled state; `manual` and `initState` apply only when it is created.
    // The default is an initially unsignaled event that releases one waiter per signal.
    // Failure leaves this value invalid. Each opener owns its handle until release or drop;
    // releasing one handle does not invalidate another opener's event.
    mtd initNamed(name: string, manual, initState = false) fail
    {
        Swag.assert(.handle == null)
        if name.count == 0 do
            fail Errors.BadParameterError{"an event name cannot be empty"}
        for byte in name
        {
            if byte == 0 or byte == '\\' do
                fail Errors.BadParameterError{"an event name cannot contain zero bytes or backslashes"}
        }

        let nativeName = Utf16.toZeroTerminated(Format.toString("Local\\%", name))
        .handle = try CreateEventW(null, manual ? TRUE : FALSE, initState ? TRUE : FALSE, nativeName.storage())
    }

    // Closes the native event handle; repeated calls do nothing.
    mtd release()
    {
        if not .handle do
            return
        CloseHandle(.handle)
        .handle = null
    }

    // Sets the event to the signaled state.
    mtd signal()
    {
        Swag.assert(.isValid())
        expect .signalStatus().raise()
    }

    // Returns the event to the unsignaled state.
    mtd reset()
    {
        Swag.assert(.isValid())
        expect .resetStatus().raise()
    }

    // Blocks the calling thread until the event is signaled.
    mtd wait()
    {
        Swag.assert(.isValid())
        expect .waitStatus().raise()
    }

    // Signals the event and returns its outcome without allocating or invoking error hooks.
    //
    // An uninitialized or invalid handle returns a failed status. Handle it later with
    // [[Core.Sync.EventStatus.raise]], after any borrowed state has been released.
    mtd signalStatus()->EventStatus
    {
        let status = setEventStatus(.handle)
        return {succeeded: status.succeeded, errorCode: status.errorCode}
    }

    // Resets the event and returns its outcome for deferred failure handling.
    //
    // Like [[Core.Sync.Event.signalStatus]], this does not assert, allocate error storage or
    // invoke error hooks, including when the handle is invalid.
    mtd resetStatus()->EventStatus
    {
        let status = resetEventStatus(.handle)
        return {succeeded: status.succeeded, errorCode: status.errorCode}
    }

    // Waits synchronously for a signal and returns its outcome for deferred failure handling.
    //
    // The wait is non-alertable and does not dispatch callbacks or messages. An invalid handle
    // returns a failed status without invoking error hooks. A successful wait observes the
    // work published by the signaling thread, as [[Core.Sync.Event.wait]] does.
    mtd waitStatus()->EventStatus
    {
        let status = waitForSingleObjectStatus(.handle, INFINITE)
        return {succeeded: status.result != WAIT_FAILED, errorCode: status.errorCode}
    }
}
