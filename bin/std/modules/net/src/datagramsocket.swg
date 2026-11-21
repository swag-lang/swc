#global public

// One received datagram, with its sender and truncation status.
struct Datagram
{
    public
    {
        endpoint:  SocketEndpoint     // Sender address and port.
        count:     u64      // Bytes copied into the receive buffer.
        truncated: bool     // The datagram contained more bytes than the receive buffer.
    }
}

// Selects the local interface used when joining an IP multicast group.
struct MulticastOptions
{
    public
    {
        interfaceAddress: IpAddress = {}     // Local IPv4 interface address; zero selects the default.
        interfaceIndex:   u32     // IPv6 interface index; zero selects the default.
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

    // Enables or disables sending IPv4 broadcast datagrams on this socket.
    mtd setBroadcast(enabled: bool) fail

    // Sets the maximum blocking receive time in milliseconds; zero disables the timeout.
    mtd setReadTimeout(timeoutMs: u32) fail

    // Joins an IPv4 or IPv6 multicast group on the selected local interface.
    mtd joinMulticast(group: IpAddress, options: MulticastOptions = {}) fail

    // Leaves a multicast group previously joined with the same address and interface.
    mtd leaveMulticast(group: IpAddress, options: MulticastOptions = {}) fail

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
