#global namespace Compress.Zstd
#global internal

using Core.Errors

struct FseEntry
{
    symbol: u8
    bits:   u8
    base:   u16
}

struct FseTable
{
    entries: [512] FseEntry
    log:     u32
    valid:   bool
}

impl FseTable
{
    mtd repeat(symbol: u8)
    {
        .entries[0] = {symbol: symbol}
        .log        = 0
        .valid      = true
    }

    mtd build(counts: const [..] s16, log: u32) fail
    {
        let size = 1_u32 << log
        var sum  = 0_u32
        for count in counts
        {
            sum += count < 0 ? 1 : cast(u32, count)
        }

        if sum != size
        {
            fail InvalidFormatError{"invalid Zstandard entropy distribution"}
        }

        var next: [256] u16
        var high = cast(s32, size) - 1
        for symbol in counts.count
        {
            let count = counts[symbol]
            if count < 0
            {
                .entries[high].symbol = cast(u8, symbol)
                high         -= 1
                next[symbol] = 1
            }
            else
            {
                next[symbol] = cast(u16, count)
            }
        }

        let step     = (size >> 1) + (size >> 3) + 3
        let mask     = size - 1
        var position = 0_u32
        for symbol in counts.count
        {
            let count = counts[symbol]
            if count <= 0
            {
                continue
            }

            for cast(u32, count)
            {
                .entries[position].symbol = cast(u8, symbol)
                position = (position + step) & mask
                while cast(s32, position) > high
                {
                    position = (position + step) & mask
                }
            }
        }

        if position
        {
            fail InvalidFormatError{"invalid Zstandard entropy spread"}
        }

        for index in size
        {
            let entry = &.entries[index]
            let state = cast(u32, next[entry.symbol])
            next[entry.symbol] += 1
            let bits = log - (31 - Math.leadingZeros(state))
            entry.bits = cast(u8, bits)
            entry.base = cast(u16, (state << bits) - size)
        }

        .log   = log
        .valid = true
    }

    mtd read(source: const [..] u8, maxSymbol, maxLog: u32)->u32 fail
    {
        var bits = ForwardBits{source: source}
        let log  = (try bits.read(4)) + 5
        if log > maxLog
        {
            fail InvalidFormatError{"Zstandard entropy log exceeds the format limit"}
        }

        var counts: [256] s16
        var remaining = (1_u32 << log) + 1
        var threshold = 1_u32 << log
        var width     = log + 1
        var symbol    = 0_u32
        while remaining > 1
        {
            if symbol > maxSymbol
            {
                fail InvalidFormatError{"too many Zstandard entropy symbols"}
            }

            let maximum = 2 * threshold - 1 - remaining
            let low     = try bits.peek(width - 1)
            var encoded = low
            if low < maximum
            {
                bits.position += width - 1
            }
            else
            {
                encoded = try bits.read(width)
                if encoded >= threshold
                {
                    encoded -= maximum
                }
            }

            let count  = cast(s32, encoded) - 1
            let weight = count < 0 ? 1_u32 : cast(u32, count)
            if weight >= remaining
            {
                fail InvalidFormatError{"invalid Zstandard entropy probability"}
            }

            counts[symbol] = cast(s16, count)
            symbol         += 1
            remaining      -= weight

            if not count
            {
                for
                {
                    let run = try bits.read(2)
                    symbol += run
                    if symbol > maxSymbol
                    {
                        fail InvalidFormatError{"Zstandard entropy zero run exceeds the alphabet"}
                    }

                    if run != 3
                    {
                        break
                    }
                }
            }

            while remaining < threshold
            {
                threshold >>= 1
                width     -= 1
            }
        }

        try .build(counts[until symbol], log)
        return (bits.position + 7) >> 3
    }
}
