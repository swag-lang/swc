#global namespace Compress.Zstd
#global internal

using Core.Errors

private struct HuffmanEntry
{
    symbol: u8
    bits:   u8
}

struct HuffmanTable
{
    private entries: [2048] HuffmanEntry
    log: u32
}

impl HuffmanTable
{
    mtd read(source: const [..] u8)->u64 fail
    {
        if not source.count
        {
            fail InvalidFormatError{"missing Zstandard Huffman description"}
        }

        var weights: [256] u8
        let header = cast(u32, source[0])
        let bytes  = header >= 128 ? ((header - 127 + 1) >> 1) : header
        if bytes > source.count - 1 or not bytes
        {
            fail InvalidFormatError{"truncated Zstandard Huffman description"}
        }

        let encoded = source[1 until 1 + bytes]
        var count   = 0_u32
        if header >= 128
        {
            count = header - 127
            for index in count
            {
                let packed = encoded[index >> 1]
                weights[index] = (index & 1) ? packed & 15 : packed >> 4
            }
        }
        else
        {
            var table: FseTable
            let offset = try table.read(encoded, 11, 6)
            var bits:  ReverseBits
            try bits.init(encoded[offset to])
            var state0 = try bits.read(table.log)
            var state1 = try bits.read(table.log)
            for
            {
                if count == 255
                {
                    fail InvalidFormatError{"too many Zstandard Huffman weights"}
                }

                let entry = table.entries[state0]
                weights[count] = entry.symbol
                count += 1
                if entry.bits > bits.remaining
                {
                    if count == 255
                    {
                        fail InvalidFormatError{"too many Zstandard Huffman weights"}
                    }

                    weights[count] = table.entries[state1].symbol
                    count += 1
                    break
                }

                let next = cast(u32, entry.base) + (try bits.read(entry.bits))
                state0 = state1
                state1 = next
            }
        }

        var sum = 0_u32
        for index in count
        {
            let weight = weights[index]
            if weight > 11
            {
                fail InvalidFormatError{"invalid Zstandard Huffman weight"}
            }

            if weight
            {
                sum += 1_u32 << (weight - 1)
            }
        }

        if not sum or sum >= 2048
        {
            fail InvalidFormatError{"invalid Zstandard Huffman weight total"}
        }

        let log     = 32 - Math.leadingZeros(sum)
        let missing = (1_u32 << log) - sum
        if missing & (missing - 1)
        {
            fail InvalidFormatError{"invalid final Zstandard Huffman weight"}
        }

        weights[count] = cast(u8, 32 - Math.leadingZeros(missing))
        count += 1

        var slot = 0_u32
        for weight in 1 to log
        {
            let span = 1_u32 << (weight - 1)
            let bits = cast(u8, log + 1 - weight)
            for symbol in count where weights[symbol] == weight
            {
                let entry = HuffmanEntry{symbol: cast(u8, symbol), bits: bits}
                for index in slot until slot + span
                {
                    .entries[index] = entry
                }

                slot += span
            }
        }

        .log = log
        return 1 + bytes
    }

    #[Swag.Inline]
    private mtd const decodeByte(bits: *ReverseBits)->u8 fail
    {
        let entry = .entries[bits.peek(.log)]
        if entry.bits > bits.remaining
        {
            fail InvalidFormatError{"truncated Zstandard Huffman literals"}
        }

        bits.remaining -= entry.bits
        return entry.symbol
    }

    mtd const decode(output: [..] u8, source: const [..] u8) fail
    {
        var bits: ReverseBits
        try bits.init(source)
        for index in output.count
        {
            output[index] = try .decodeByte(&bits)
        }

        if bits.remaining
        {
            fail InvalidFormatError{"unused Zstandard Huffman literal bits"}
        }
    }

    mtd const decodeFour(output: [..] u8, source: const [..] u8) fail
    {
        let segment = (output.count + 3) / 4
        if source.count < 6 or segment * 3 > output.count
        {
            fail InvalidFormatError{"invalid Zstandard Huffman jump table"}
        }

        var bits: [4] ReverseBits
        var cursor = 6_u64
        for stream in 3
        {
            let size = readLittle(source.buffer + stream * 2, 2)
            if size > source.count - cursor
            {
                fail InvalidFormatError{"truncated Zstandard Huffman stream"}
            }

            try bits[stream].init(source[cursor until cursor + size])
            cursor += size
        }

        try bits[3].init(source[cursor to])

        let output0 = output.buffer
        let output1 = output0 + segment
        let output2 = output1 + segment
        let output3 = output2 + segment
        let common  = output.count - segment * 3
        for index in common
        {
            output0[index] = try .decodeByte(&bits[0])
            output1[index] = try .decodeByte(&bits[1])
            output2[index] = try .decodeByte(&bits[2])
            output3[index] = try .decodeByte(&bits[3])
        }

        for index in common until segment
        {
            output0[index] = try .decodeByte(&bits[0])
            output1[index] = try .decodeByte(&bits[1])
            output2[index] = try .decodeByte(&bits[2])
        }

        for stream in bits where stream.remaining
        {
            fail InvalidFormatError{"unused Zstandard Huffman literal bits"}
        }
    }
}

struct LiteralDecoder
{
    table:  HuffmanTable
    buffer: Array!{u8}
}

impl LiteralDecoder
{
    mtd decode(source: const [..] u8, limit: u64)->{ literals: const [..] u8, consumed: u64 } fail
    {
        if not source.count
        {
            fail InvalidFormatError{"missing Zstandard literal section"}
        }

        let kind   = source[0] & 3
        let format = (source[0] >> 2) & 3
        if kind < 2
        {
            let headerSize = format & 1 ? (format == 1 ? 2_u32 : 3) : 1_u32
            if headerSize > source.count
            {
                fail InvalidFormatError{"truncated Zstandard literal header"}
            }

            let size   = readLittle(source.buffer, headerSize) >> (headerSize == 1 ? 3 : 4)
            let stored = kind == 0 ? size : 1
            if size > limit or stored > source.count - headerSize
            {
                fail InvalidFormatError{"Zstandard literals exceed the block size"}
            }

            if kind == 0
            {
                return {literals: source[headerSize until headerSize + size], consumed: headerSize + size}
            }

            .buffer.grow(size)
            .buffer.count = size
            if size
            {
                Memory.set(.buffer.storage(), source[headerSize], size)
            }

            return {literals: .buffer.toSlice(), consumed: headerSize + 1}
        }

        let headerSize = format < 2 ? 3_u32 : cast(u32, format + 2)
        if headerSize > source.count
        {
            fail InvalidFormatError{"truncated Zstandard Huffman literal header"}
        }

        let width  = 10 + (headerSize - 3) * 4
        let header = readLittle(source.buffer, headerSize)
        let size   = (header >> 4) & ((1_u64 << width) - 1)
        let stored = header >> (4 + width)
        if size > limit or stored > source.count - headerSize
        {
            fail InvalidFormatError{"Zstandard Huffman literals exceed the block size"}
        }

        let encoded = source[headerSize until headerSize + stored]
        var streams = 0_u64
        if kind == 2
        {
            streams = try .table.read(encoded)
        }
        else if not .table.log
        {
            fail InvalidFormatError{"Zstandard literal section repeats a missing table"}
        }

        .buffer.grow(size)
        .buffer.count = size
        if format == 0
        {
            try .table.decode(.buffer.toSlice(), encoded[streams to])
        }
        else
        {
            try .table.decodeFour(.buffer.toSlice(), encoded[streams to])
        }

        return {literals: .buffer.toSlice(), consumed: headerSize + stored}
    }
}
