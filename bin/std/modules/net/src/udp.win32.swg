#global if #os == Swag.TargetOs.Windows
#global export

using Win32

private func newDatagramSocket(family: s32)->SOCKET fail
{
    try startup()
    let handle = socket(family, SOCK_DGRAM, IPPROTO_UDP)
    if handle == INVALID_SOCKET
    {
        let code = WSAGetLastError()
        discard WSACleanup()
        fail NetworkError{code: code}
    }
    return handle
}

impl DatagramSocket
{
    // Binds an IPv4 or IPv6 endpoint and returns an owned socket.
    //
    // A port of zero selects an available port, which [[Net.DatagramSocket.localAddress]] returns.
    func bind(endpoint: SocketEndpoint)->DatagramSocket fail
    {
        if endpoint.address.family != .IPv4 and endpoint.address.family != .IPv6 do
            fail Errors.BadParameterError{}
        let family = endpoint.address.family == .IPv4 ? AF_INET : AF_INET6
        let handle = try newDatagramSocket(family)
        let address = nativeSocketAddress(endpoint)
        let length = cast(s32, endpoint.address.family == .IPv4 ? #sizeof(SOCKADDR_IN) : #sizeof(SOCKADDR_IN6))
        if Win32.bind(handle, cast(const *SOCKADDR, cast(const *void, &address)), length) == SOCKET_ERROR
        {
            let code = WSAGetLastError()
            closeNetSocket(handle)
            fail NetworkError{code: code}
        }
        return {handle: handle, open: true}
    }

    // Binds an IPv4 endpoint.
    func bind(endpoint: Endpoint)->DatagramSocket fail
    {
        return try .bind(endpoint.toSocketEndpoint())
    }

    // Returns the bound IPv4 or IPv6 address and port.
    mtd localAddress()->SocketEndpoint fail
    {
        Swag.assert(.open)
        var address: NativeSocketAddress
        var size = cast(s32, #sizeof(NativeSocketAddress))
        if getsockname(.handle, cast(*SOCKADDR, cast(*void, &address)), &size) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        return try portableSocketEndpoint(cast(const *SOCKADDR, cast(const *void, &address)))
    }

    // Sends one complete datagram. A zero-byte payload is a valid datagram.
    mtd sendTo(endpoint: SocketEndpoint, bytes: const [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if bytes.count > cast(u64, Swag.S32.Max) do
            fail Errors.BadParameterError{}
        if endpoint.address.family != .IPv4 and endpoint.address.family != .IPv6 do
            fail Errors.BadParameterError{}
        let address = nativeSocketAddress(endpoint)
        let length = cast(s32, endpoint.address.family == .IPv4 ? #sizeof(SOCKADDR_IN) : #sizeof(SOCKADDR_IN6))
        let result = sendto(.handle, bytes.buffer, cast(s32, bytes.count), 0,
                            cast(const *SOCKADDR, cast(const *void, &address)), length)
        if result == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        if cast(u64, result) != bytes.count do
            fail NetworkError{"datagram send did not transfer the complete message", code: 10040}
        return cast(u64, result)
    }

    // Receives one datagram; oversized messages are truncated to `buffer.count` bytes.
    mtd receiveFrom(buffer: [..] u8)->Datagram fail
    {
        Swag.assert(.open)
        var address: NativeSocketAddress
        var size = cast(s32, #sizeof(NativeSocketAddress))
        let capacity = Math.min(buffer.count, cast(u64, Swag.S32.Max))
        let result = recvfrom(.handle, buffer.buffer, cast(s32, capacity), 0,
                              cast(*SOCKADDR, cast(*void, &address)), &size)
        if result == SOCKET_ERROR
        {
            let code = WSAGetLastError()
            if code == WSAEMSGSIZE do
                return {endpoint: try portableSocketEndpoint(cast(const *SOCKADDR, cast(const *void, &address))),
                        count: capacity, truncated: true}
            fail NetworkError{code: code}
        }
        return {endpoint: try portableSocketEndpoint(cast(const *SOCKADDR, cast(const *void, &address))),
                count: cast(u64, result), truncated: false}
    }
}
