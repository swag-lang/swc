#global public

// Owns a blocking TCP connection; it cannot be copied.
#[Swag.NoCopy]
struct TcpStream
{
    handle: u64
    open:   bool
}

impl TcpStream
{
    // Returns whether this stream still owns a connection.
    mtd const isOpen()->bool => .open

    // Closes the connection; repeated calls do nothing.
    mtd close()
    {
        if .open
        {
            closeTcpSocket(.handle)
            .open = false
        }
    }

    // Closes the connection when this owner is dropped.
    mtd opDrop() { .close() }
}
