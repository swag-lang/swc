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
    // Enables or disables sending IPv4 broadcast datagrams on this socket.
    mtd setBroadcast(enabled: bool) fail
    {
        Swag.assert(.open)
        let value = enabled ? 1's32 : 0's32
        if setsockopt(.handle, SOL_SOCKET, SO_BROADCAST, cast(const *u8, &value), #sizeof(s32)) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
    }

    // Joins an IPv4 or IPv6 multicast group on the selected local interface.
    mtd joinMulticast(group: IpAddress, options: MulticastOptions = {}) fail
    {
        try setMulticastMembership(.handle, group, options, true)
    }

    // Leaves a multicast group previously joined with the same address and interface.
    mtd leaveMulticast(group: IpAddress, options: MulticastOptions = {}) fail
    {
        try setMulticastMembership(.handle, group, options, false)
    }

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

private func setMulticastMembership(handle: SOCKET, group: IpAddress, options: MulticastOptions, join: bool) fail
{
    if group.isIPv4()
    {
        if group.bytes[0] < 224 or group.bytes[0] > 239 or not options.interfaceAddress.isIPv4() do
            fail Errors.BadParameterError{}
        var request: IP_MREQ
        request.imr_multiaddr.S_un.S_addr = htonl((cast(u32, group.bytes[0]) << 24) |
            (cast(u32, group.bytes[1]) << 16) | (cast(u32, group.bytes[2]) << 8) | group.bytes[3])
        request.imr_interface.S_un.S_addr = htonl((cast(u32, options.interfaceAddress.bytes[0]) << 24) |
            (cast(u32, options.interfaceAddress.bytes[1]) << 16) |
            (cast(u32, options.interfaceAddress.bytes[2]) << 8) | options.interfaceAddress.bytes[3])
        let option = join ? IP_ADD_MEMBERSHIP : IP_DROP_MEMBERSHIP
        if setsockopt(handle, IPPROTO_IP, option, cast(const *u8, &request), #sizeof(IP_MREQ)) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        return
    }

    if group.isIPv6() and group.bytes[0] == 0xFF
    {
        var request: IPV6_MREQ
        for i in 16 do
            request.ipv6mr_multiaddr.Byte[i] = group.bytes[i]
        request.ipv6mr_interface = options.interfaceIndex
        let option = join ? IPV6_JOIN_GROUP : IPV6_LEAVE_GROUP
        if setsockopt(handle, IPPROTO_IPV6, option, cast(const *u8, &request), #sizeof(IPV6_MREQ)) == SOCKET_ERROR do
            fail NetworkError{code: WSAGetLastError()}
        return
    }

    fail Errors.BadParameterError{}
}
