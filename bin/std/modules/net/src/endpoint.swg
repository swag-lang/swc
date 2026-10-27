#global export

// An IPv4 address and TCP port in host byte order.
struct Endpoint
{
    public
    {
        address: [4] u8     // IPv4 octets in their usual display order.
        port:    u16        // TCP port; zero asks the host to choose a listening port.
    }
}
