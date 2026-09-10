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
