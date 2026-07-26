#global if WINDOWS
#global public
#global namespace Sync

using Win32

#[Swag.NoCopy]
struct Event
{
    handle: #null HANDLE
}

impl Event
{
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
        Debug.assert(.handle == null)
        .handle = expect CreateEventA(null, manual ? TRUE : FALSE, initState ? TRUE : FALSE, null)
    }

    // Destroy an existing event
    mtd release()
    {
        if !.handle do
            return
        CloseHandle(.handle)
        .handle = null
    }

    // Signal the event
    mtd signal()
    {
        Debug.assert(.isValid())
        expect SetEvent(.handle)
    }

    // Reset the event state
    mtd reset()
    {
        Debug.assert(.isValid())
        expect ResetEvent(.handle)
    }

    // Wait for the event to be signaled
    mtd wait()
    {
        Debug.assert(.isValid())
        expect WaitForSingleObject(.handle, INFINITE)
    }
}
