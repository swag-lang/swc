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
            closeNetSocket(.handle)
            .open = false
        }
    }

    // Stops sending bytes while keeping the receive side open.
    mtd shutdownWrite() fail

    // Reads exactly `buffer.count` bytes, retrying partial reads.
    //
    // Returns zero for an empty buffer; EOF before the buffer is full fails with
    // [[Net.NetworkError]].
    mtd readExact(buffer: [..] u8)->u64 fail
    {
        var total = 0'u64
        while total < buffer.count
        {
            let count = try .read(buffer[total to])
            if count == 0 do
                fail NetworkError{"TCP stream ended before the requested bytes arrived", code: 0}
            total += count
        }

        return total
    }

    // Writes all bytes, retrying partial writes.
    //
    // Returns zero for an empty buffer; a write that makes no progress fails with
    // [[Net.NetworkError]].
    mtd writeAll(bytes: const [..] u8)->u64 fail
    {
        var total = 0'u64
        while total < bytes.count
        {
            let count = try .write(bytes[total to])
            if count == 0 do
                fail NetworkError{"TCP stream stopped before all bytes were written", code: 0}
            total += count
        }

        return total
    }

    // Closes the connection when this owner is dropped.
    mtd opDrop() { .close() }

    // Enables or disables Nagle's algorithm for this connection.
    mtd setNoDelay(enabled: bool) fail

    // Enables or disables operating-system TCP keepalive probes for this connection.
    mtd setKeepAlive(enabled: bool) fail

    // Sets the maximum blocking read time in milliseconds; zero disables the timeout.
    mtd setReadTimeout(timeoutMs: u32) fail

    // Sets the maximum blocking write time in milliseconds; zero disables the timeout.
    mtd setWriteTimeout(timeoutMs: u32) fail
}
