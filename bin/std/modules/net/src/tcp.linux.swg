#global if #os == Swag.TargetOs.Linux
#global export

using Core

private func newSocket(family: s32)->s32 fail
{
    let handle = Linux.socket(family, Linux.SOCK_STREAM | Linux.SOCK_CLOEXEC, Linux.IPPROTO_TCP)
    if handle < 0 do
        fail NetworkError{code: Linux.errno()}
    return handle
}

internal func closeNetSocket(handle: u64)
{
    // Linux retires the descriptor even when close reports EINTR; retrying could close a new owner.
    discard Linux.close(cast(s32, handle))
}

private func finishInterruptedConnect(handle: s32) fail
{
    var descriptor = Linux.pollfd{fd: handle, events: Linux.POLLOUT}
    for
    {
        if Linux.poll(&descriptor, 1, -1) >= 0 do
            break
        let code = Linux.errno()
        if code != Linux.EINTR do
            fail NetworkError{code: code}
    }

    var code: s32
    var size = cast(u32, #sizeof(s32))
    if Linux.getsockopt(handle, Linux.SOL_SOCKET, Linux.SO_ERROR, &code, &size) < 0 do
        fail NetworkError{code: Linux.errno()}
    if code != 0 do
        fail NetworkError{code: code}
}

impl TcpStream
{
    // Enables or disables Nagle's algorithm for this connection.
    mtd setNoDelay(enabled: bool) fail
    {
        Swag.assert(.open)
        let value = enabled ? 1's32 : 0's32
        if Linux.setsockopt(cast(s32, .handle), Linux.IPPROTO_TCP, Linux.TCP_NODELAY,
                            cast(const *void, &value), #sizeof(s32)) < 0 do
            fail NetworkError{code: Linux.errno()}
    }

    // Enables or disables operating-system TCP keepalive probes for this connection.
    mtd setKeepAlive(enabled: bool) fail
    {
        Swag.assert(.open)
        let value = enabled ? 1's32 : 0's32
        if Linux.setsockopt(cast(s32, .handle), Linux.SOL_SOCKET, Linux.SO_KEEPALIVE,
                            cast(const *void, &value), #sizeof(s32)) < 0 do
            fail NetworkError{code: Linux.errno()}
    }

    // Sets the maximum blocking read time in milliseconds; zero disables the timeout.
    mtd setReadTimeout(timeoutMs: u32) fail
    {
        Swag.assert(.open)
        let timeout = Linux.timeval{tv_sec: cast(s64, timeoutMs / 1000),
                                    tv_usec: cast(s64, (timeoutMs % 1000) * 1000)}
        if Linux.setsockopt(cast(s32, .handle), Linux.SOL_SOCKET, Linux.SO_RCVTIMEO,
                            cast(const *void, &timeout), #sizeof(Linux.timeval)) < 0 do
            fail NetworkError{code: Linux.errno()}
    }

    // Connects to an IPv4 or IPv6 endpoint, returning an owned blocking stream.
    func connect(endpoint: SocketEndpoint)->TcpStream fail
    {
        if endpoint.address.family != .IPv4 and endpoint.address.family != .IPv6 do
            fail Errors.BadParameterError{}
        let family = endpoint.address.family == .IPv4 ? Linux.AF_INET : Linux.AF_INET6
        let handle = try newSocket(family)
        defer #fail closeNetSocket(cast(u64, handle))
        let address = nativeSocketAddress(endpoint)
        var result: s32
        if endpoint.address.family == .IPv4
        {
            result = Linux.connect(handle, cast(const *Linux.sockaddr, cast(const *void, &address)), #sizeof(Linux.sockaddr_in))
        }
        else
        {
            result = Linux.connect(handle, cast(const *Linux.sockaddr, cast(const *void, &address)), #sizeof(Linux.sockaddr_in6))
        }
        if result < 0
        {
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}

            try finishInterruptedConnect(handle)
        }

        return {handle: cast(u64, handle), open: true}
    }

    // Connects to an IPv4 endpoint, returning an owned blocking stream.
    func connect(endpoint: Endpoint)->TcpStream fail
    {
        return try .connect(endpoint.toSocketEndpoint())
    }

    // Stops sending bytes while keeping the receive side open.
    mtd shutdownWrite() fail
    {
        Swag.assert(.open)
        if Linux.shutdown(cast(s32, .handle), Linux.SHUT_WR) < 0 do
            fail NetworkError{code: Linux.errno()}
    }

    // Reads up to `buffer.count` bytes; zero indicates EOF or an empty buffer.
    mtd read(buffer: [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if buffer.count == 0 do
            return 0
        let count = Math.min(buffer.count, cast(u64, Swag.S64.Max))
        for
        {
            let result = Linux.recv(cast(s32, .handle), buffer.buffer, count, 0)
            if result >= 0 do
                return cast(u64, result)
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}
        }
    }

    // Writes up to `buffer.count` bytes and returns the amount accepted by the host.
    //
    // A closed peer reports [[Net.NetworkError]] without raising SIGPIPE in the process.
    mtd write(buffer: const [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if buffer.count == 0 do
            return 0
        let count = Math.min(buffer.count, cast(u64, Swag.S64.Max))
        for
        {
            let result = Linux.send(cast(s32, .handle), buffer.buffer, count, Linux.MSG_NOSIGNAL)
            if result >= 0 do
                return cast(u64, result)
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}
        }
    }
}

impl TcpListener
{
    // Binds an IPv4 endpoint and starts listening for connections.
    //
    // Port zero selects an available port, which [[Net.TcpListener.localEndpoint]] returns.
    func listen(endpoint: SocketEndpoint, backlog = 16)->TcpListener fail
    {
        if backlog <= 0 do
            fail Errors.BadParameterError{}
        if endpoint.address.family != .IPv4 and endpoint.address.family != .IPv6 do
            fail Errors.BadParameterError{}
        let family = endpoint.address.family == .IPv4 ? Linux.AF_INET : Linux.AF_INET6
        let handle  = try newSocket(family)
        let address = nativeSocketAddress(endpoint)
        let length = cast(u32, endpoint.address.family == .IPv4 ? #sizeof(Linux.sockaddr_in) : #sizeof(Linux.sockaddr_in6))
        if Linux.bind(handle, cast(const *Linux.sockaddr, cast(const *void, &address)), length) < 0 or
           Linux.listen(handle, backlog) < 0
        {
            let code = Linux.errno()
            closeNetSocket(cast(u64, handle))
            fail NetworkError{code: code}
        }

        return {handle: cast(u64, handle), open: true}
    }

    // Binds an IPv4 endpoint and starts listening for connections.
    func listen(endpoint: Endpoint, backlog = 16)->TcpListener fail
    {
        return try .listen(endpoint.toSocketEndpoint(), backlog)
    }

    // Returns the bound local address and port.
    mtd localEndpoint()->Endpoint fail
    {
        let endpoint = try .localAddress()
        if endpoint.address.family != .IPv4 do
            fail Errors.BadParameterError{}
        var octets: [4] u8
        for i in octets.count do
            octets[i] = endpoint.address.bytes[i]
        return {address: octets, port: endpoint.port}
    }

    // Returns the bound local IPv4 or IPv6 address and port.
    mtd localAddress()->SocketEndpoint fail
    {
        Swag.assert(.open)
        var address: NativeSocketAddress
        var size = cast(u32, #sizeof(NativeSocketAddress))
        if Linux.getsockname(cast(s32, .handle), cast(*Linux.sockaddr, cast(*void, &address)), &size) < 0 do
            fail NetworkError{code: Linux.errno()}
        return try portableSocketEndpoint(cast(const *Linux.sockaddr, cast(const *void, &address)))
    }

    // Blocks until a peer connects and returns an independently owned stream.
    mtd accept()->TcpStream fail
    {
        Swag.assert(.open)
        for
        {
            let handle = Linux.accept4(cast(s32, .handle), null, null, Linux.SOCK_CLOEXEC)
            if handle >= 0 do
                return {handle: cast(u64, handle), open: true}
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}
        }
    }
}
