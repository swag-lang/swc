#global if #os == Swag.TargetOs.Windows
#global export

using Core, Win32

private func startup() fail
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

private func nativeAddress(endpoint: Endpoint)->SOCKADDR_IN
{
    var address: SOCKADDR_IN
    address.sin_family                = AF_INET
    address.sin_port                  = htons(endpoint.port)
    address.sin_addr.S_un.S_un_b.s_b1 = endpoint.address[0]
    address.sin_addr.S_un.S_un_b.s_b2 = endpoint.address[1]
    address.sin_addr.S_un.S_un_b.s_b3 = endpoint.address[2]
    address.sin_addr.S_un.S_un_b.s_b4 = endpoint.address[3]
    return address
}

private func newSocket()->SOCKET fail
{
    try startup()
    let handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    if handle == INVALID_SOCKET
    {
        let code = WSAGetLastError()
        discard WSACleanup()
        fail NetworkError{code: code}
    }

    return handle
}

private func closeSocket(handle: SOCKET)
{
    discard closesocket(handle)
    discard WSACleanup()
}

impl TcpStream
{
    // Connects to an IPv4 endpoint, returning an owned blocking stream.
    func connect(endpoint: Endpoint)->TcpStream fail
    {
        let handle  = try newSocket()
        let address = nativeAddress(endpoint)
        if Win32.connect(handle, cast(const *SOCKADDR, cast(const *void, &address)), #sizeof(SOCKADDR_IN)) == SOCKET_ERROR
        {
            let code = WSAGetLastError()
            closeSocket(handle)
            fail NetworkError{code: code}
        }

        return {handle: handle, open: true}
    }

    // Returns whether this stream still owns a connection.
    mtd const isOpen()->bool => .open

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

    // Closes the connection; repeated calls do nothing.
    mtd close()
    {
        if .open
        {
            closeSocket(.handle)
            .open = false
        }
    }

    // Closes the connection when this owner is dropped.
    mtd opDrop() { .close() }
}

impl TcpListener
{
    // Binds an IPv4 endpoint and starts listening for connections.
    //
    // Port zero selects an available port, which [[Net.TcpListener.localEndpoint]] returns.
    func listen(endpoint: Endpoint, backlog = 16)->TcpListener fail
    {
        if backlog <= 0 do
            fail Errors.BadParameterError{}
        let handle  = try newSocket()
        let address = nativeAddress(endpoint)
        if bind(handle, cast(const *SOCKADDR, cast(const *void, &address)), #sizeof(SOCKADDR_IN)) == SOCKET_ERROR or
           Win32.listen(handle, backlog) == SOCKET_ERROR
        {
            let code = WSAGetLastError()
            closeSocket(handle)
            fail NetworkError{code: code}
        }

        return {handle: handle, open: true}
    }

    // Returns the bound local address and port.
    mtd localEndpoint()->Endpoint fail
    {
        Swag.assert(.open)
        var address: SOCKADDR_IN
        var size = cast(s32, #sizeof(SOCKADDR_IN))
        if getsockname(.handle, cast(*SOCKADDR, cast(*void, &address)), &size) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        let bytes = address.sin_addr.S_un.S_un_b
        return {address: [bytes.s_b1, bytes.s_b2, bytes.s_b3, bytes.s_b4], port: ntohs(address.sin_port)}
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

    // Closes the listener; repeated calls do nothing.
    mtd close()
    {
        if .open
        {
            closeSocket(.handle)
            .open = false
        }
    }

    // Closes the listener when this owner is dropped.
    mtd opDrop() { .close() }
}
