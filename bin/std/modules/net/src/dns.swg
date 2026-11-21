#global public

// Selects the Internet Protocol address families returned by a DNS lookup.
enum AddressFamilyFilter
{
    Any // Return IPv4 and IPv6 results in resolver order.
    IPv4 // Return only IPv4 results.
    IPv6 // Return only IPv6 results.
}

// Controls which address families a DNS lookup returns.
struct ResolveOptions
{
    public family: AddressFamilyFilter = .Any     // Address families included in the result.
}

// Resolves host names using the operating system's configured resolver.
namespace Dns
{
    // Resolves a host synchronously, preserving the operating-system address order.
    //
    // Resolution blocks in the platform resolver. The port is copied into each result; resolution
    // itself does not open a socket. An empty host fails with [[Core.Errors.BadParameterError]],
    // while a host that cannot be resolved fails with [[Net.NetworkError]].
    func resolve(host: string, port: u16 = 0, options: ResolveOptions = {})->Array'SocketEndpoint fail
    {
        if host.count == 0 do
            fail Errors.BadParameterError{}
        for i in host.count do
            if host[i] == 0 do
                fail Errors.BadParameterError{}
        return try resolveNative(host, port, options)
    }
}
