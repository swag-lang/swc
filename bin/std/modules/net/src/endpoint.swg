#global export

// Identifies which Internet Protocol address family an address uses.
enum AddressFamily
{
    IPv4     // A 32-bit Internet Protocol version 4 address.
    IPv6     // A 128-bit Internet Protocol version 6 address.
}

// Represents an IPv4 or IPv6 address as network-order octets.
struct IpAddress
{
    public
    {
        family:  AddressFamily     // Address format used by the first 4 or 16 octets.
        bytes:   [16] u8           // Address bytes in network order; unused IPv4 bytes are zero.
        scopeId: u32               // IPv6 interface scope for link-local addresses; zero otherwise.
    }
}

impl IpAddress
{
    // Creates an IPv4 address from its four display-order octets.
    func ipv4(octets: [4] u8)->IpAddress
    {
        var result = IpAddress{family: .IPv4}
        for i in 4 do
            result.bytes[i] = octets[i]
        return result
    }

    // Creates an IPv6 address from its sixteen network-order octets.
    func ipv6(octets: [16] u8, scopeId: u32 = 0)->IpAddress => IpAddress{family: .IPv6, bytes: octets, scopeId: scopeId}

    // Returns whether this address is IPv4.
    mtd const isIPv4()->bool => .family == .IPv4

    // Returns whether this address is IPv6.
    mtd const isIPv6()->bool => .family == .IPv6
}

// An IP address and TCP or UDP port in host byte order.
struct SocketEndpoint
{
    public
    {
        address: IpAddress     // IPv4 or IPv6 address.
        port:    u16           // Port in host byte order; zero asks the host to choose one when binding.
    }
}

// An IPv4 address and port in host byte order for TCP or UDP.
struct Endpoint
{
    public
    {
        address: [4] u8     // IPv4 octets in their usual display order.
        port:    u16        // Port; zero asks the host to choose one when binding.
    }
}

impl Endpoint
{
    // Converts this IPv4 endpoint to the address family independent form.
    mtd const toSocketEndpoint()->SocketEndpoint => {address: IpAddress.ipv4(.address), port: .port}
}
