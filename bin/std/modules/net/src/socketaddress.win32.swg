#global if #os == Swag.TargetOs.Windows
#global internal

using Win32

union NativeSocketAddress
{
    address4: SOCKADDR_IN
    address6: SOCKADDR_IN6
}

internal func nativeSocketAddress(endpoint: SocketEndpoint)->NativeSocketAddress
{
    var result: NativeSocketAddress
    if endpoint.address.family == .IPv4
    {
        result.address4.sin_family = AF_INET
        result.address4.sin_port = htons(endpoint.port)
        result.address4.sin_addr.S_un.S_un_b.s_b1 = endpoint.address.bytes[0]
        result.address4.sin_addr.S_un.S_un_b.s_b2 = endpoint.address.bytes[1]
        result.address4.sin_addr.S_un.S_un_b.s_b3 = endpoint.address.bytes[2]
        result.address4.sin_addr.S_un.S_un_b.s_b4 = endpoint.address.bytes[3]
    }
    else
    {
        result.address6.sin6_family = AF_INET6
        result.address6.sin6_port = htons(endpoint.port)
        result.address6.sin6_flowinfo = 0
        result.address6.sin6_scope_id = endpoint.address.scopeId
        for i in 16 do
            result.address6.sin6_addr.u6_addr.Byte[i] = endpoint.address.bytes[i]
    }
    return result
}

internal func portableSocketEndpoint(address: const *SOCKADDR)->SocketEndpoint fail
{
    if address.sa_family == AF_INET
    {
        let ipv4 = cast(const *SOCKADDR_IN, cast(const *void, address))
        let bytes = ipv4.sin_addr.S_un.S_un_b
        return {address: IpAddress.ipv4([bytes.s_b1, bytes.s_b2, bytes.s_b3, bytes.s_b4]),
                port: ntohs(ipv4.sin_port)}
    }
    if address.sa_family == AF_INET6
    {
        let ipv6 = cast(const *SOCKADDR_IN6, cast(const *void, address))
        var octets: [16] u8
        for i in octets.count do
            octets[i] = ipv6.sin6_addr.u6_addr.Byte[i]
        return {address: IpAddress.ipv6(octets, ipv6.sin6_scope_id), port: ntohs(ipv6.sin6_port)}
    }

    fail NetworkError{"socket returned an unsupported address family", code: 10047}
}
