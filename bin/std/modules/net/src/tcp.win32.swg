#global if #os == Swag.TargetOs.Windows
#global export

using Core, Win32

internal func startup() fail
{
    var data: WSADATA
    let code = WSAStartup(0x0202, &data)
    if code != 0 do
        fail NetworkError{code: code}
    if data.wVersion != 0x0202
    {
        discard WSACleanup()
        fail NetworkError{code: WSAVERNOTSUPPORTED}
    }
}

private func newSocket(family: s32)->SOCKET fail
{
    try startup()
    let handle = socket(family, SOCK_STREAM, IPPROTO_TCP)
    if handle == INVALID_SOCKET
    {
        let code = WSAGetLastError()
        discard WSACleanup()
        fail NetworkError{code: code}
    }

    return handle
}

internal func closeNetSocket(handle: u64)
{
    discard closesocket(handle)
    discard WSACleanup()
}

impl TcpStream
{
    // Enables or disables Nagle's algorithm for this connection.
    mtd setNoDelay(enabled: bool) fail
    {
        Swag.assert(.open)
        let value = enabled ? 1's32 : 0's32
        if setsockopt(.handle, IPPROTO_TCP, TCP_NODELAY, cast(const *u8, &value), #sizeof(s32)) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
    }

    // Enables or disables operating-system TCP keepalive probes for this connection.
    mtd setKeepAlive(enabled: bool) fail
    {
        Swag.assert(.open)
        let value = enabled ? 1's32 : 0's32
        if setsockopt(.handle, SOL_SOCKET, SO_KEEPALIVE, cast(const *u8, &value), #sizeof(s32)) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
    }

    // Connects to an IPv4 or IPv6 endpoint, returning an owned blocking stream.
    func connect(endpoint: SocketEndpoint)->TcpStream fail
    {
        if endpoint.address.family != .IPv4 and endpoint.address.family != .IPv6 do
            fail Errors.BadParameterError{}
        let family = endpoint.address.family == .IPv4 ? AF_INET : AF_INET6
        let handle  = try newSocket(family)
        let address = nativeSocketAddress(endpoint)
        let length = cast(s32, endpoint.address.family == .IPv4 ? #sizeof(SOCKADDR_IN) : #sizeof(SOCKADDR_IN6))
        if Win32.connect(handle, cast(const *SOCKADDR, cast(const *void, &address)), length) == SOCKET_ERROR
        {
            let code = WSAGetLastError()
            closeNetSocket(handle)
            fail NetworkError{code: code}
        }

        return {handle: handle, open: true}
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
        if shutdown(.handle, SD_SEND) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
    }

    // Reads up to `buffer.count` bytes; zero indicates EOF or an empty buffer.
    mtd read(buffer: [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if buffer.count == 0 do
            return 0
        let count  = cast(s32, Math.min(buffer.count, cast(u64, Swag.S32.Max)))
        let result = recv(.handle, buffer.buffer, count, 0)
        if result == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        return cast(u64, result)
    }

    // Writes up to `buffer.count` bytes and returns the amount accepted by the host.
    mtd write(buffer: const [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if buffer.count == 0 do
            return 0
        let count  = cast(s32, Math.min(buffer.count, cast(u64, Swag.S32.Max)))
        let result = send(.handle, buffer.buffer, count, 0)
        if result == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        return cast(u64, result)
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
        let family = endpoint.address.family == .IPv4 ? AF_INET : AF_INET6
        let handle  = try newSocket(family)
        let address = nativeSocketAddress(endpoint)
        let length = cast(s32, endpoint.address.family == .IPv4 ? #sizeof(SOCKADDR_IN) : #sizeof(SOCKADDR_IN6))
        if bind(handle, cast(const *SOCKADDR, cast(const *void, &address)), length) == SOCKET_ERROR or
           Win32.listen(handle, backlog) == SOCKET_ERROR
        {
            let code = WSAGetLastError()
            closeNetSocket(handle)
            fail NetworkError{code: code}
        }

        return {handle: handle, open: true}
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
        var size = cast(s32, #sizeof(NativeSocketAddress))
        if getsockname(.handle, cast(*SOCKADDR, cast(*void, &address)), &size) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        return try portableSocketEndpoint(cast(const *SOCKADDR, cast(const *void, &address)))
    }

    // Blocks until a peer connects and returns an independently owned stream.
    mtd accept()->TcpStream fail
    {
        Swag.assert(.open)
        try startup()
        let handle = Win32.accept(.handle, null, null)
        if handle == INVALID_SOCKET
        {
            let code = WSAGetLastError()
            discard WSACleanup()
            fail NetworkError{code: code}
        }

        return {handle: handle, open: true}
    }
}
