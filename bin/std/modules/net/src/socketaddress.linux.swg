#global if #os == Swag.TargetOs.Linux
#global internal

using Linux

union NativeSocketAddress
{
    address4: sockaddr_in
    address6: sockaddr_in6
}

internal func nativeSocketAddress(endpoint: SocketEndpoint)->NativeSocketAddress
{
    var result: NativeSocketAddress
    if endpoint.address.family == .IPv4
    {
        var octets: [4] u8
        for i in octets.count do
            octets[i] = endpoint.address.bytes[i]
        result.address4 = sockaddr_in{
            sin_family: cast(u16, AF_INET),
            sin_port: htons(endpoint.port),
            sin_addr: {s_addr: htonl((cast(u32, octets[0]) << 24) | (cast(u32, octets[1]) << 16) |
                                    (cast(u32, octets[2]) << 8) | octets[3])}}
    }
    else
    {
        result.address6.sin6_family = cast(u16, AF_INET6)
        result.address6.sin6_port = htons(endpoint.port)
        result.address6.sin6_flowinfo = 0
        result.address6.sin6_scope_id = endpoint.address.scopeId
        for i in 16 do
            result.address6.sin6_addr.s6_addr[i] = endpoint.address.bytes[i]
    }
    return result
}

internal func portableSocketEndpoint(address: const *sockaddr)->SocketEndpoint fail
{
    if address.sa_family == cast(u16, AF_INET)
    {
        let ipv4 = cast(const *sockaddr_in, cast(const *void, address))
        let bits = ntohl(ipv4.sin_addr.s_addr)
        let ip = IpAddress.ipv4([cast(u8, bits >> 24), cast(u8, (bits >> 16) & 0xFF),
                                 cast(u8, (bits >> 8) & 0xFF), cast(u8, bits & 0xFF)])
        return {address: ip, port: ntohs(ipv4.sin_port)}
    }
    if address.sa_family == cast(u16, AF_INET6)
    {
        let ipv6 = cast(const *sockaddr_in6, cast(const *void, address))
        var octets: [16] u8
        for i in octets.count do
            octets[i] = ipv6.sin6_addr.s6_addr[i]
        return {address: IpAddress.ipv6(octets, ipv6.sin6_scope_id), port: ntohs(ipv6.sin6_port)}
    }

    fail NetworkError{"socket returned an unsupported address family", code: 97}
}
