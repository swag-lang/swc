#global public

// Owns a blocking TCP listener; it cannot be copied.
#[Swag.NoCopy]
struct TcpListener
{
    handle: u64
    open:   bool
}

impl TcpListener
{
    // Closes the listener; repeated calls do nothing. A blocked `accept` is not guaranteed to wake.
    mtd close()
    {
        if .open
        {
            closeNetSocket(.handle)
            .open = false
        }
    }

    // Closes the listener when this owner is dropped.
    mtd opDrop() { .close() }
}
