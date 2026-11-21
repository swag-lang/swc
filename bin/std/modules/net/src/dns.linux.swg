#global if #os == Swag.TargetOs.Linux
#global internal

using Linux

internal func resolveNative(host: string, service: const [*]u8?, port: u16, options: ResolveOptions)->Array'SocketEndpoint fail
{
    let family = options.family == .IPv4 ? AF_INET : options.family == .IPv6 ? AF_INET6 : AF_UNSPEC
    var hints: addrinfo
    hints.ai_family   = family
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP
    var result: *addrinfo?
    let code = getaddrinfo(host.buffer, service, &hints, &result)
    if code != 0 do
        fail NetworkError{"host name resolution failed", code: code}
    let first = unwrap result
    defer freeaddrinfo(first)

    var endpoints: Array'SocketEndpoint
    var current:   *addrinfo? = result
    while current
    {
        let item = current
        if item.ai_addr and (item.ai_family == AF_INET or item.ai_family == AF_INET6)
        {
            var endpoint = try portableSocketEndpoint(item.ai_addr)
            if service == null do
                endpoint.port = port
            endpoints.add(endpoint)
        }

        current = item.ai_next
    }

    if endpoints.isEmpty() do
        fail NetworkError{"host name resolution returned no IP addresses", code: -5}
    return endpoints
}
