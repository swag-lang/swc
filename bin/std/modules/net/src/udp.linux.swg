#global if #os == Swag.TargetOs.Linux
#global export

using Linux

private func newDatagramSocket(family: s32)->s32 fail
{
    let handle = Linux.socket(family, Linux.SOCK_DGRAM | Linux.SOCK_CLOEXEC, Linux.IPPROTO_UDP)
    if handle < 0 do
        fail NetworkError{code: Linux.errno()}
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
        let family = endpoint.address.family == .IPv4 ? Linux.AF_INET : Linux.AF_INET6
        let handle = try newDatagramSocket(family)
        let address = nativeSocketAddress(endpoint)
        let length = cast(u32, endpoint.address.family == .IPv4 ? #sizeof(Linux.sockaddr_in) : #sizeof(Linux.sockaddr_in6))
        if Linux.bind(handle, cast(const *Linux.sockaddr, cast(const *void, &address)), length) < 0
        {
            let code = Linux.errno()
            closeNetSocket(cast(u64, handle))
            fail NetworkError{code: code}
        }

        return {handle: cast(u64, handle), open: true}
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
        var size = cast(u32, #sizeof(NativeSocketAddress))
        if Linux.getsockname(cast(s32, .handle), cast(*Linux.sockaddr, cast(*void, &address)), &size) < 0 do
            fail NetworkError{code: Linux.errno()}
        return try portableSocketEndpoint(cast(const *Linux.sockaddr, cast(const *void, &address)))
    }

    // Sends one complete datagram. A zero-byte payload is a valid datagram.
    mtd sendTo(endpoint: SocketEndpoint, bytes: const [..] u8)->u64 fail
    {
        Swag.assert(.open)
        if endpoint.address.family != .IPv4 and endpoint.address.family != .IPv6 do
            fail Errors.BadParameterError{}
        let address = nativeSocketAddress(endpoint)
        let length = cast(u32, endpoint.address.family == .IPv4 ? #sizeof(Linux.sockaddr_in) : #sizeof(Linux.sockaddr_in6))
        let result = Linux.sendto(cast(s32, .handle), bytes.buffer, bytes.count, 0,
                                  cast(const *Linux.sockaddr, cast(const *void, &address)), length)
        if result < 0 do
            fail NetworkError{code: Linux.errno()}
        if cast(u64, result) != bytes.count do
            fail NetworkError{"datagram send did not transfer the complete message", code: 5}
        return cast(u64, result)
    }

    // Receives one datagram; oversized messages are truncated to `buffer.count` bytes.
    mtd receiveFrom(buffer: [..] u8)->Datagram fail
    {
        Swag.assert(.open)
        var address: NativeSocketAddress
        var size = cast(u32, #sizeof(NativeSocketAddress))
        for
        {
            let result = Linux.recvfrom(cast(s32, .handle), buffer.buffer, buffer.count, Linux.MSG_TRUNC,
                                        cast(*Linux.sockaddr, cast(*void, &address)), &size)
            if result >= 0
            {
                let received = cast(u64, result)
                return {endpoint: try portableSocketEndpoint(cast(const *Linux.sockaddr, cast(const *void, &address))),
                        count: Math.min(received, buffer.count), truncated: received > buffer.count}
            }
            let code = Linux.errno()
            if code != Linux.EINTR do
                fail NetworkError{code: code}
        }
    }
}
