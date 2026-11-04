#global if #os == Swag.TargetOs.Linux
#global public
#global namespace Hardware

// Returns the logical processor count permitted by the calling thread's Linux affinity mask.
//
// Returns one if the operating system cannot resolve the mask. CPU bandwidth quotas do not
// change affinity and are not reflected in this count.
func processorCount()->u32
{
    var mask: [1024] u8
    if Linux.sched_getaffinity(0, #sizeof(mask), &mask[0]) != 0 do
        return 1
    var count = 0'u32
    for byte in mask
    {
        var remaining = byte
        while remaining
        {
            count     += 1
            remaining &= remaining - 1
        }
    }

    return count == 0 ? 1 : count
}

// Returns the first non-loopback six-byte adapter address packed into the low bytes, or zero if unavailable.
//
// The first address byte occupies the least significant byte. Enumeration order is chosen by
// the operating system; this is not a stable machine identity and virtual adapters can be returned.
func macAddress()->u64
{
    var first: *Linux.ifaddrs?
    if Linux.getifaddrs(&first) != 0 or not first do
        return 0
    defer Linux.freeifaddrs(unwrap first)
    var current = first
    while current
    {
        let adapter = current
        current = adapter.ifa_next
        if (adapter.ifa_flags & Linux.IFF_LOOPBACK) != 0 or not adapter.ifa_addr do
            continue
        let address = adapter.ifa_addr
        if address.sa_family != Linux.AF_PACKET do
            continue
        let link = cast(const *Linux.sockaddr_ll, cast(const *void, address))
        if link.sll_halen != 6 do
            continue
        var result = 0'u64
        for i in 6 do
            result |= cast(u64, link.sll_addr[i]) << (i * 8)
        if result != 0 do
            return result
    }

    return 0
}
