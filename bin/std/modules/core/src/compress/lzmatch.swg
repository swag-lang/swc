#global namespace Compress
#global internal

struct LzMatchFinder
{
    positions: Array'u32
    shift:     u32
}

impl LzMatchFinder
{
    mtd init(size: u64)
    {
        let slots = Math.roundUpToPowerOf2(cast(u32, Math.clamp(size, 256'u64, 16384'u64)))
        .positions.resize(slots)
        .shift = Math.leadingZeros(slots) + 1
    }

    #[Swag.Inline, Swag.Safety(.Overflow, false)]
    mtd const hash(word: u32)->u32 => (word * 0x9E3779B1'u32) >> .shift

    mtd find(source: const [*] u8, start, lastStart, matchEnd: u64)->{ at: u64, distance: u64, length: u64 }
    {
        let positions = .positions.storage()
        var at        = start
        var misses    = 32'u64
        while at <= lastStart
        {
            let word     = cast(const [*] u32, source + at)[0]
            let slot     = .hash(word)
            let previous = cast(u64, positions[slot])
            positions[slot] = cast(u32, at + 1)

            let distance = at + 1 - previous
            if previous and
               distance <= Swag.U16.Max and
               cast(const [*] u32, source + at - distance)[0] == word
            {
                let length = matchLength(source + at, source + at - distance, matchEnd - at)
                let end    = at + length
                if end <= lastStart
                {
                    let preceding = cast(const [*] u32, source + end - 1)[0]
                    positions[.hash(preceding)] = cast(u32, end)
                }

                return {at: at, distance: distance, length: length}
            }

            // Probe sparsely through long literal runs, resuming at full density after a match.
            at     += Math.min(misses >> 5, 32'u64)
            misses += 1
        }

        return {at: 0, distance: 0, length: 0}
    }
}

private func matchLength(current, previous: const [*] u8, limit: u64)->u64
{
    var length = 4'u64
    while limit - length >= 8
    {
        let different = cast(const [*] u64, current + length)[0] ^ cast(const [*] u64, previous + length)[0]
        if different do
            return length + (Math.trailingZeros(Math.littleEndianToNative(different)) >> 3)
        length += 8
    }

    while length < limit and current[length] == previous[length] do
        length += 1
    return length
}

// Copies a validated LZ back-reference, extending a repeated prefix when it overlaps the output.
#[Swag.Inline]
func copyLzMatch(output: [*] u8, distance, length: u64)
{
    let from = output - distance
    if distance >= 8 and length >= 8
    {
        var copied = 0'u64
        while length - copied >= 8
        {
            cast([*] u64, output + copied)[0] = cast(const [*] u64, from + copied)[0]
            copied += 8
        }

        // The last word may overwrite part of the preceding store. Its source has
        // already been produced because the distance is at least a word.
        if copied < length do
            cast([*] u64, output + length - 8)[0] = cast(const [*] u64, from + length - 8)[0]
        return
    }

    if distance >= 4 and length >= 4 and length <= 8
    {
        cast([*] u32, output)[0] = cast(const [*] u32, from)[0]
        cast([*] u32, output + length - 4)[0] = cast(const [*] u32, from + length - 4)[0]
        return
    }

    if distance == 1
    {
        Memory.set(output, from[0], length)
        return
    }

    var copied = Math.min(distance, length)
    Memory.copy(output, from, copied)
    while copied < length
    {
        let amount = Math.min(copied, length - copied)
        Memory.copy(output + copied, output, amount)
        copied += amount
    }
}

#[Swag.Inline]
func lzBuffersOverlap(output: [..] u8, input: const [..] u8)->bool
{
    return output.count != 0 and
           input.count != 0 and
           input.buffer < output.buffer + output.count and
           output.buffer < input.buffer + input.count
}
