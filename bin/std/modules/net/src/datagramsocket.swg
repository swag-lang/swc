#global public

// One received datagram, with its sender and truncation status.
struct Datagram
{
    public
    {
        endpoint:  SocketEndpoint     // Sender address and port.
        count:     u64                // Bytes copied into the receive buffer.
        truncated: bool               // The datagram contained more bytes than the receive buffer.
    }
}

// Owns a blocking UDP socket; it cannot be copied.
#[Swag.NoCopy]
struct DatagramSocket
{
    handle: u64
    open:   bool
}

impl DatagramSocket
{
    // Returns whether this socket still owns a native handle.
    mtd const isOpen()->bool => .open

    // Closes the socket; repeated calls do nothing.
    mtd close()
    {
        if .open
        {
            closeNetSocket(.handle)
            .open = false
        }
    }

    // Closes the socket when this owner is dropped.
    mtd opDrop() { .close() }
}
