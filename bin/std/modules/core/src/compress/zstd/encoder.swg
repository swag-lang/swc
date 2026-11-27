#global namespace Compress.Zstd

internal struct(Alphabet: u32, States: u32) EncodeTable
{
    first:   [Alphabet] u8
    inverse: [Alphabet, States] u8
    entries: [States] FseEntry
    log:     u32
}

internal func(Alphabet: u32, States: u32) prepareEncoding(distribution: const [..] s16, log: u32)->EncodeTable!{Alphabet, States}
{
    var table: FseTable
    expect table.build(distribution, log)
    var result: #returntype
    result.log = log
    for state in States
    {
        let entry = table.entries[state]
        result.entries[state]      = entry
        result.first[entry.symbol] = cast(u8, state)
        let first = cast(u32, entry.base)
        let count = 1_u32 << entry.bits
        for next in first until first + count
        {
            result.inverse[entry.symbol, next] = cast(u8, state)
        }
    }

    return result
}

private const LiteralEncoding = #run prepareEncoding!{36, 64}(LiteralDistribution, 6)
private const OffsetEncoding  = #run prepareEncoding!{29, 32}(OffsetDistribution, 5)
private const MatchEncoding   = #run prepareEncoding!{53, 64}(MatchDistribution, 6)

private const SmallLiterals = #run
{
    var result: [64] u8
    for code in 25
    {
        let start = LiteralBase[code]
        for size in start until start + (1_u32 << LiteralExtra[code])
        {
            result[size] = cast(u8, code)
        }
    }

    return result
}

private const SmallMatches = #run
{
    var result: [131] u8
    for code in 43
    {
        let start = MatchBase[code]
        for size in start until start + (1_u32 << MatchExtra[code])
        {
            result[size] = cast(u8, code)
        }
    }

    return result
}

private struct Sequence
{
    literals: u32
    match:    u32
    distance: u32
}

internal struct ReverseWriter
{
    bits:  u64
    width: u32
}

internal impl ReverseWriter
{
    #[Swag.Inline]
    mtd write(output: *Array!{u8}, value, count: u32)
    {
        .bits  |= cast(u64, value) << .width
        .width += count
        if .width >= 32
        {
            cast([*] u32, output.emplaceAddress(4))[0] = Math.nativeToLittleEndian(cast #wrap (u32, .bits))
            .bits  >>= 32
            .width -= 32
        }
    }

    mtd finish(output: *Array!{u8})
    {
        .write(output, 1, 1)
        .flush(output)
    }

    mtd flush(output: *Array!{u8})
    {
        appendLittle(output, .bits, (.width + 7) >> 3)
        .bits  = 0
        .width = 0
    }
}

#[Swag.Inline]
internal func appendLittle(output: *Array!{u8}, value: u64, count: u32)
{
    let buffer = output.emplaceAddress(count)
    for index in count
    {
        buffer[index] = Math.byteAt(value, index)
    }
}

private struct BlockEncoder
{
    finder:    LzMatchFinder
    literals:  Array!{u8}
    sequences: Array!{Sequence}
    encoded:   Array!{u8}
    huffman:   HuffmanEncoder
}

private impl BlockEncoder
{
    mtd encode(block: const [..] u8, level: CompressionLevel)
    {
        .literals.clear()
        .sequences.clear()
        .encoded.clear()
        if block.count < 5
        {
            return
        }

        .finder.init(block.count)
        var literalStart = 0_u64
        let lastStart    = block.count - 4
        while literalStart <= lastStart
        {
            let match = .finder.find(block.buffer, literalStart, lastStart, block.count)
            if not match.length
            {
                break
            }

            let size = match.at - literalStart
            .literals.add(block[literalStart until match.at])
            .sequences.add({literals: cast(u32, size), match: cast(u32, match.length), distance: cast(u32, match.distance)})
            literalStart = match.at + match.length
        }

        if not .sequences.count and level == .Fast
        {
            return
        }

        .literals.add(block[literalStart to])
        .writeLiterals(level)
        .writeSequences()
    }

    mtd writeLiterals(level: CompressionLevel)
    {
        let size = .literals.count
        if level == .Balanced and size >= 64 and .huffman.write(&.encoded, .literals.toSlice())
        {
            return
        }

        if size < 32
        {
            .encoded.add(cast(u8, size << 3))
        }
        else if size < 4096
        {
            appendLittle(&.encoded, (size << 4) | 4, 2)
        }
        else
        {
            appendLittle(&.encoded, (size << 4) | 12, 3)
        }

        .encoded.add(.literals.toSlice())
    }

    mtd writeSequences()
    {
        let count = .sequences.count
        if not count
        {
            .encoded.add(0)
            return
        }

        if count < 128
        {
            .encoded.add(cast(u8, count))
        }
        else if count < 0x7F00
        {
            .encoded.add(cast(u8, 128 + (count >> 8)))
            .encoded.add(Math.byteAt(count, 0))
        }
        else
        {
            .encoded.add(255)
            appendLittle(&.encoded, count - 0x7F00, 2)
        }

        // All three alphabets use the format's predefined probability tables.
        .encoded.add(0)
        var bits: ReverseWriter
        var litState, offState, matchState: u32
        for reverseIndex in count
        {
            let sequence  = .sequences[count - 1 - reverseIndex]
            let offset    = sequence.distance + 3
            let litCode   = sequence.literals < 64 ? cast(u32, SmallLiterals[sequence.literals]) : 50 - Math.leadingZeros(sequence.literals)
            let offCode   = 31 - Math.leadingZeros(offset)
            let matchCode = sequence.match < 131 ? cast(u32, SmallMatches[sequence.match]) : 67 - Math.leadingZeros(sequence.match - 3)

            if reverseIndex
            {
                let newLitState   = LiteralEncoding.inverse[litCode, litState]
                let newOffState   = OffsetEncoding.inverse[offCode, offState]
                let newMatchState = MatchEncoding.inverse[matchCode, matchState]
                let litEntry      = LiteralEncoding.entries[newLitState]
                let offEntry      = OffsetEncoding.entries[newOffState]
                let matchEntry    = MatchEncoding.entries[newMatchState]
                bits.write(&.encoded, offState - offEntry.base, offEntry.bits)
                bits.write(&.encoded, matchState - matchEntry.base, matchEntry.bits)
                bits.write(&.encoded, litState - litEntry.base, litEntry.bits)
                litState   = newLitState
                offState   = newOffState
                matchState = newMatchState
            }
            else
            {
                litState   = LiteralEncoding.first[litCode]
                offState   = OffsetEncoding.first[offCode]
                matchState = MatchEncoding.first[matchCode]
            }

            bits.write(&.encoded, sequence.literals - LiteralBase[litCode], LiteralExtra[litCode])
            bits.write(&.encoded, sequence.match - MatchBase[matchCode], MatchExtra[matchCode])
            bits.write(&.encoded, offset - (1_u32 << offCode), offCode)
        }

        bits.write(&.encoded, matchState, MatchEncoding.log)
        bits.write(&.encoded, offState, OffsetEncoding.log)
        bits.write(&.encoded, litState, LiteralEncoding.log)
        bits.finish(&.encoded)
    }
}

private func isRepeated(block: const [..] u8)->bool
{
    let value   = block[0]
    let pattern = Math.Simd.splat(value)
    var index   = 0_u64
    while block.count - index >= 16
    {
        if Math.Simd.anyTrue(Math.Simd.load(block.buffer + index) != pattern)
        {
            return false
        }

        index += 16
    }

    for tail in index until block.count where block[tail] != value
    {
        return false
    }

    return true
}

// Selects the time spent compressing a Zstandard frame.
public enum CompressionLevel
{
    Fast         // Uses greedy matches and stored literals.
    Balanced     // Adds a Huffman table when it reduces the literals.
}

// Compresses `buffer` into an owned Zstandard frame with a content checksum.
//
// Both levels use greedy matches and the predefined sequence tables. `level` selects
// whether to try Huffman coding for the literals. The encoder stores any block verbatim
// when compressing it would increase its size.
public func compress(buffer: const [..] u8, level = CompressionLevel.Fast)->Array!{u8}
{
    var result: #returntype
    appendLittle(&result, Magic, 4)
    let size      = buffer.count
    let single    = size <= MaxBlock
    let sizeWidth = size < 256 ? 1_u32 : size < 65792 ? 2_u32 : size <= Swag.U32.Max ? 4_u32 : 8_u32
    let flags     = (Math.trailingZeros(sizeWidth) << 6) | (single ? 32 : 0) | 4
    result.add(cast(u8, flags))
    if not single
    {
        result.add((17 - 10) << 3)
    }

    appendLittle(&result, sizeWidth == 2 ? size - 256 : size, sizeWidth)

    var encoder: BlockEncoder
    var cursor = 0_u64
    for
    {
        let blockSize = Math.min(MaxBlock, size - cursor)
        let last      = cursor + blockSize == size
        let block     = buffer[cursor until cursor + blockSize]
        let lastBit   = last ? 1_u64 : 0_u64
        if blockSize > 1 and isRepeated(block)
        {
            appendLittle(&result, (blockSize << 3) | 2 | lastBit, 3)
            result.add(block[0])
        }
        else
        {
            encoder.encode(block, level)
            let packed = encoder.encoded.toSlice()
            if packed.count and packed.count < blockSize
            {
                appendLittle(&result, (packed.count << 3) | 4 | lastBit, 3)
                result.add(packed)
            }
            else
            {
                appendLittle(&result, (blockSize << 3) | lastBit, 3)
                result.add(block)
            }
        }

        if last
        {
            break
        }

        cursor += blockSize
    }

    appendLittle(&result, contentChecksum(buffer), 4)
    return result
}
