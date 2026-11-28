#global namespace Compress.Zstd
#global internal

using Core.Errors

const LiteralBase: [36] u32 = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    16, 18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048, 4096,
    8192, 16384, 32768, 65536]
const LiteralExtra: [36] u8 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12,
    13, 14, 15, 16]
const MatchBase: [53] u32 = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
    19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
    35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027, 2051,
    4099, 8195, 16387, 32771, 65539]
const MatchExtra: [53] u8 = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 2, 2, 3, 3, 4, 4, 5, 7, 8, 9, 10, 11,
    12, 13, 14, 15, 16]

const LiteralDistribution: [36] s16 = [
    4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1,
    -1, -1, -1, -1]
const MatchDistribution: [53] s16 = [
    1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1,
    -1, -1, -1, -1, -1]
const OffsetDistribution: [29] s16 = [
    1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1]

struct SequenceDecoder
{
    literal: FseTable
    offset:  FseTable
    match:   FseTable
    repeats: [3] u64 = [1, 4, 8]
}

private func loadTable(table: *FseTable, source: const [..] u8, mode: u8, distribution: const [..] s16, defaultLog, maxSymbol, maxLog: u32)->u32 fail
{
    switch mode
    {
    case 0:
        try table.build(distribution, defaultLog)
        return 0

    case 1:
        if not source.count or source[0] > maxSymbol
        {
            fail InvalidFormatError{"invalid Zstandard run-length sequence symbol"}
        }

        table.repeat(source[0])
        return 1

    case 2:
        return try table.read(source, maxSymbol, maxLog)

    default:
        if not table.valid
        {
            fail InvalidFormatError{"Zstandard sequence section repeats a missing table"}
        }

        return 0
    }
}

private func failBlockCapacity(limited: bool) fail
{
    if limited
    {
        fail UnsupportedFormatError{"Zstandard output exceeds the configured limit"}
    }

    fail InvalidFormatError{"Zstandard sequences exceed the block size"}
}

impl SequenceDecoder
{
    #[Swag.Inline]
    private mtd distance(value, literalCount: u64)->u64 fail
    {
        var offset: u64
        var index = 3_u64
        if value > 3
        {
            offset = value - 3
        }
        else
        {
            index = value - 1 + (literalCount ? 0 : 1)
            if index == 3
            {
                if .repeats[0] <= 1
                {
                    fail InvalidFormatError{"invalid Zstandard repeat offset"}
                }

                offset = .repeats[0] - 1
            }
            else
            {
                offset = .repeats[index]
            }
        }

        if index >= 2
        {
            .repeats[2] = .repeats[1]
        }

        if index >= 1
        {
            .repeats[1] = .repeats[0]
            .repeats[0] = offset
        }

        return offset
    }

    mtd decode(output: [..] u8, history, window: u64, literals, source: const [..] u8, limited: bool)->u64 fail
    {
        if not source.count
        {
            fail InvalidFormatError{"missing Zstandard sequence count"}
        }

        let first = cast(u32, source[0])
        if not first
        {
            if source.count != 1
            {
                fail InvalidFormatError{"unused Zstandard sequence bytes"}
            }

            if literals.count > output.count - history
            {
                try failBlockCapacity(limited)
            }

            if literals.count
            {
                Memory.copy(output.buffer + history, literals.buffer, literals.count)
            }

            return literals.count
        }

        var count  = first
        var cursor = 1_u64
        if first >= 128
        {
            let width = first == 255 ? 2_u32 : 1_u32
            if width > source.count - cursor
            {
                fail InvalidFormatError{"truncated Zstandard sequence count"}
            }

            let tail = cast(u32, readLittle(source.buffer + cursor, width))
            count  = first == 255 ? tail + 0x7F00 : ((first - 128) << 8) | tail
            cursor += width
        }

        if cursor == source.count or not count
        {
            fail InvalidFormatError{"invalid Zstandard sequence count or mode"}
        }

        let modes = source[cursor]
        if modes & 3
        {
            fail InvalidFormatError{"Zstandard sequence mode has reserved bits set"}
        }

        cursor += 1

        cursor += try loadTable(&.literal, source[cursor to], modes >> 6, LiteralDistribution, 6, 35, 9)
        cursor += try loadTable(&.offset, source[cursor to], (modes >> 4) & 3, OffsetDistribution, 5, 31, 8)
        cursor += try loadTable(&.match, source[cursor to], (modes >> 2) & 3, MatchDistribution, 6, 52, 9)

        var bits: ReverseBits
        try bits.init(source[cursor to])
        var litState   = try bits.read(.literal.log)
        var offState   = try bits.read(.offset.log)
        var matchState = try bits.read(.match.log)
        var written    = history
        var literalAt  = 0_u64
        for index in count
        {
            let litEntry   = .literal.entries[litState]
            let offEntry   = .offset.entries[offState]
            let matchEntry = .match.entries[matchState]
            let litBits    = cast(u32, LiteralExtra[litEntry.symbol])
            let matchBits  = cast(u32, MatchExtra[matchEntry.symbol])
            let lengthBits = litBits + matchBits
            let valueBits  = lengthBits + offEntry.symbol
            var fields:      u64
            var offsetExtra: u64
            if valueBits <= 56
            {
                fields      = try bits.readGroup(valueBits)
                offsetExtra = fields >> lengthBits
            }
            else
            {
                offsetExtra = try bits.read(offEntry.symbol)
                fields      = try bits.readGroup(lengthBits)
            }

            let offsetValue  = (1_u64 << offEntry.symbol) + offsetExtra
            let matchExtra   = (fields >> litBits) & ((1_u64 << matchBits) - 1)
            let literalExtra = fields & ((1_u64 << litBits) - 1)
            let matchBytes   = cast(u64, MatchBase[matchEntry.symbol]) + matchExtra
            let litBytes     = cast(u64, LiteralBase[litEntry.symbol]) + literalExtra
            let distance     = try .distance(offsetValue, litBytes)

            if litBytes > literals.count - literalAt or
               distance > window or
               distance > written + litBytes
            {
                fail InvalidFormatError{"Zstandard sequence exceeds its literals or history"}
            }

            if litBytes + matchBytes > output.count - written
            {
                try failBlockCapacity(limited)
            }

            if litBytes
            {
                Memory.copy(output.buffer + written, literals.buffer + literalAt, litBytes)
                literalAt += litBytes
                written   += litBytes
            }

            Compress.copyLzMatch!{true}(output.buffer + written, distance, matchBytes)
            written += matchBytes

            if index + 1 != count
            {
                let lowBits   = cast(u32, offEntry.bits)
                let midBits   = cast(u32, matchEntry.bits)
                let lowAndMid = lowBits + midBits
                let states    = try bits.read(lowAndMid + litEntry.bits)
                litState   = cast(u32, litEntry.base) + (states >> lowAndMid)
                matchState = cast(u32, matchEntry.base) + ((states >> lowBits) & ((1_u32 << midBits) - 1))
                offState   = cast(u32, offEntry.base) + (states & ((1_u32 << lowBits) - 1))
            }
        }

        if bits.remaining
        {
            fail InvalidFormatError{"unused Zstandard sequence bits"}
        }

        let remaining = literals.count - literalAt
        if remaining > output.count - written
        {
            try failBlockCapacity(limited)
        }

        if remaining
        {
            Memory.copy(output.buffer + written, literals.buffer + literalAt, remaining)
        }

        return written + remaining - history
    }
}
