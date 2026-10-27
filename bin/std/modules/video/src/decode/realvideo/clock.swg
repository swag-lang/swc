#global namespace RealVideo
#global internal

using Core, Core.Errors

// Legacy Matroska muxers can stamp B pictures after their future reference. The codec's
// wrapping millisecond clock restores their presentation time relative to that reference.
struct Clock
{
    anchorTime:  s64
    anchorClock: s32
    hasAnchor:   bool
}

impl Clock
{
    mtd presentationTime(data, prefix: const [..] u8, containerTime: s64)->s64 fail
    {
        let length = data.count + prefix.count
        if not length do
            fail InvalidFormatError{"RealVideo packet is empty"}
        let header = 1 + (cast(u64, packetByte(data, prefix, 0)) + 1) * 8
        if length < header + 4 do
            fail InvalidFormatError{"RealVideo packet has no picture clock"}
        var value = 0'u32
        for i in 4'u64 do
            value = (value << 8) | cast(u32, packetByte(data, prefix, header + i))
        let kind  = (value >> 29) & 3
        let clock = cast(s32, ((value >> 6) & 8191))
        if kind != 3
        {
            .anchorTime  = containerTime
            .anchorClock = clock
            .hasAnchor   = true
            return containerTime
        }

        if not .hasAnchor do
            return containerTime
        let behind = (.anchorClock - clock + 8192) & 8191
        return .anchorTime - cast(s64, behind) * 1_000_000
    }
}

private func packetByte(data, prefix: const [..] u8, at: u64)->u8 => at < prefix.count ? prefix[at] : data[at - prefix.count]
