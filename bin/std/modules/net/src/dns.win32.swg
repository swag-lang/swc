#global if #os == Swag.TargetOs.Windows
#global internal

using Win32

internal func resolveNative(host: string, port: u16, options: ResolveOptions)->Array'SocketEndpoint fail
{
    try startup()
    defer discard WSACleanup()
    let family = options.family == .IPv4 ? AF_INET : options.family == .IPv6 ? AF_INET6 : AF_UNSPEC
    var hints: ADDRINFOA
    hints.ai_family = family
    hints.ai_socktype = SOCK_STREAM
    hints.ai_protocol = IPPROTO_TCP
    var result: *ADDRINFOA?
    let code = getaddrinfo(host.buffer, null, &hints, &result)
    if code != 0 do
        fail NetworkError{"host name resolution failed", code: code}
    let first = unwrap result
    defer freeaddrinfo(first)

    var endpoints: Array'SocketEndpoint
    var current: *ADDRINFOA? = result
    while current
    {
        let item = current
        if item.ai_addr and (item.ai_family == AF_INET or item.ai_family == AF_INET6)
        {
            let endpoint = try portableSocketEndpoint(item.ai_addr)
            endpoints.add({address: endpoint.address, port: port})
        }
        current = item.ai_next
    }
    if endpoints.isEmpty() do
        fail NetworkError{"host name resolution returned no IP addresses", code: 11001}
    return endpoints
}
