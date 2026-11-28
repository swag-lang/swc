#global namespace Compress.Zstd
#global internal

private const Prime1 = 0x9E3779B185EBCA87_u64
private const Prime2 = 0xC2B2AE3D27D4EB4F_u64
private const Prime3 = 0x165667B19E3779F9_u64
private const Prime4 = 0x85EBCA77C2B2AE63_u64
private const Prime5 = 0x27D4EB2F165667C5_u64

#[Swag.Inline, Swag.Safety(.Overflow, false)]
private func hashRound(value, word: u64)->u64 => Swag.rol(value + word * Prime2, 31) * Prime1

#[Swag.Inline, Swag.Safety(.Overflow, false)]
private func mergeLane(hash, value: u64)->u64 => (hash ^ hashRound(0, value)) * Prime1 + Prime4

// The Zstandard content checksum stores the lower 32 bits of XXH64.
#[Swag.Safety(.Overflow, false)]
func contentChecksum(bytes: const [..] u8)->u32
{
    var offset = 0_u64
    var hash   = Prime5
    if bytes.count >= 32
    {
        var lane0 = Prime1 + #wrap Prime2
        var lane1 = Prime2
        var lane2 = 0_u64
        var lane3 = 0_u64 - #wrap Prime1
        while bytes.count - offset >= 32
        {
            let input = bytes.buffer + offset
            lane0  = hashRound(lane0, readLe64(input))
            lane1  = hashRound(lane1, readLe64(input + 8))
            lane2  = hashRound(lane2, readLe64(input + 16))
            lane3  = hashRound(lane3, readLe64(input + 24))
            offset += 32
        }

        hash = Swag.rol(lane0, 1) + Swag.rol(lane1, 7) + Swag.rol(lane2, 12) + Swag.rol(lane3, 18)
        hash = mergeLane(hash, lane0)
        hash = mergeLane(hash, lane1)
        hash = mergeLane(hash, lane2)
        hash = mergeLane(hash, lane3)
    }

    hash += bytes.count
    while bytes.count - offset >= 8
    {
        hash   = Swag.rol(hash ^ hashRound(0, readLe64(bytes.buffer + offset)), 27) * Prime1 + Prime4
        offset += 8
    }

    if bytes.count - offset >= 4
    {
        hash   = Swag.rol(hash ^ (cast(u64, readLe32(bytes.buffer + offset)) * Prime1), 23) * Prime2 + Prime3
        offset += 4
    }

    for index in offset until bytes.count
    {
        hash = Swag.rol(hash ^ (cast(u64, bytes[index]) * Prime5), 11) * Prime1
    }

    hash = (hash ^ (hash >> 33)) * Prime2
    hash = (hash ^ (hash >> 29)) * Prime3
    return cast #wrap (u32, (hash ^ (hash >> 32)))
}
