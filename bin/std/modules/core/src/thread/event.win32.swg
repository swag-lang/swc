#global if WINDOWS
#global public
#global namespace Sync

using Win32

// Represents event.
#[Swag.NoCopy]
struct Event
{
    public handle: HANDLE?     // Handle associated with this value.
}

impl Event
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .release()
    }

    // Returns true if the event is valid
    mtd isValid()->bool
    {
        return .handle != null
    }

    // Creates a new event
    func create()->Event
    {
        var result: retval
        result.init()
        return result
    }

    // Initialize event
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
        for byte in cast(const [..] u8) name
        {
            if byte == 0 or byte == '\\' do
                fail Errors.BadParameterError{"an event name cannot contain zero bytes or backslashes"}
        }

        let nativeName = Utf16.toZeroTerminated(Format.toString("Local\\%", name))
        .handle = try CreateEventW(null, manual ? TRUE : FALSE, initState ? TRUE : FALSE, nativeName.storage())
    }

    // Destroy an existing event
    mtd release()
    {
        if not .handle do
            return
        CloseHandle(.handle)
        .handle = null
    }

    // Signal the event
    mtd signal()
    {
        Swag.assert(.isValid())
        expect SetEvent(.handle)
    }

    // Reset the event state
    mtd reset()
    {
        Swag.assert(.isValid())
        expect ResetEvent(.handle)
    }

    // Wait for the event to be signaled
    mtd wait()
    {
        Swag.assert(.isValid())
        expect WaitForSingleObject(.handle, INFINITE)
    }
}
