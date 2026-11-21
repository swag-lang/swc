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
    // Enables or disables sending IPv4 broadcast datagrams on this socket.
    mtd setBroadcast(enabled: bool) fail
    {
        Swag.assert(.open)
        let value = enabled ? 1's32 : 0's32
        if Linux.setsockopt(cast(s32, .handle), Linux.SOL_SOCKET, Linux.SO_BROADCAST,
                            cast(const *void, &value), #sizeof(s32)) < 0 do
            fail NetworkError{code: Linux.errno()}
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

private func setMulticastMembership(handle: u64, group: IpAddress, options: MulticastOptions, join: bool) fail
{
    if group.isIPv4()
    {
        if group.bytes[0] < 224 or group.bytes[0] > 239 or not options.interfaceAddress.isIPv4() do
            fail Errors.BadParameterError{}
        let groupAddress = Linux.in_addr{s_addr: Linux.htonl((cast(u32, group.bytes[0]) << 24) |
            (cast(u32, group.bytes[1]) << 16) | (cast(u32, group.bytes[2]) << 8) | group.bytes[3])}
        let interfaceAddress = Linux.in_addr{s_addr: Linux.htonl((cast(u32, options.interfaceAddress.bytes[0]) << 24) |
            (cast(u32, options.interfaceAddress.bytes[1]) << 16) |
            (cast(u32, options.interfaceAddress.bytes[2]) << 8) | options.interfaceAddress.bytes[3])}
        let request = Linux.ip_mreq{imr_multiaddr: groupAddress, imr_interface: interfaceAddress}
        let option = join ? Linux.IP_ADD_MEMBERSHIP : Linux.IP_DROP_MEMBERSHIP
        if Linux.setsockopt(cast(s32, handle), Linux.IPPROTO_IP, option,
                            cast(const *void, &request), #sizeof(Linux.ip_mreq)) < 0 do
            fail NetworkError{code: Linux.errno()}
        return
    }

    if group.isIPv6() and group.bytes[0] == 0xFF
    {
        var address: Linux.in6_addr
        for i in 16 do
            address.s6_addr[i] = group.bytes[i]
        let request = Linux.ipv6_mreq{ipv6mr_multiaddr: address, ipv6mr_interface: options.interfaceIndex}
        let option = join ? Linux.IPV6_JOIN_GROUP : Linux.IPV6_LEAVE_GROUP
        if Linux.setsockopt(cast(s32, handle), Linux.IPPROTO_IPV6, option,
                            cast(const *void, &request), #sizeof(Linux.ipv6_mreq)) < 0 do
            fail NetworkError{code: Linux.errno()}
        return
    }

    fail Errors.BadParameterError{}
}
