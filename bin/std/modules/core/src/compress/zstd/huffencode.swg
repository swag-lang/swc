#global namespace Compress.Zstd
#global internal

// One fixed distribution encodes the complete weight alphabet. Its table log is six.
private const WeightDistribution: [12] s16 = [22, 10, 6, 6, 4, 4, 3, 3, 2, 2, 1, 1]
private const WeightEncoding = #run prepareEncoding!{12, 64}(WeightDistribution, 6)

struct HuffmanEncoder
{
    private lengths: [256] u8
    private codes:   [256] u16
    private encoded: Array!{u8}
}

#[Swag.Inline]
private func takeNode(nodes: const [*] u32, leaves, count: u32, leafAt, branchAt: *u32)->u32
{
    if leafAt[] < leaves and (branchAt[] == count or nodes[leafAt[]] <= nodes[branchAt[]])
    {
        let index = leafAt[]
        leafAt[] += 1
        return index
    }

    let index = branchAt[]
    branchAt[] += 1
    return index
}

impl HuffmanEncoder
{
    private mtd makeCodes(input: const [..] u8)->{ width: u32, lastSymbol: u32 }
    {
        var counts: [256] u32
        for byte in input
        {
            counts[byte] += 1
        }

        var nodes: [511] u32
        var leaves     = 0_u32
        var lastSymbol = 0_u32
        for symbol in counts.count where counts[symbol]
        {
            nodes[leaves] = (counts[symbol] << 8) | cast(u32, symbol)
            leaves        += 1
            lastSymbol    = cast(u32, symbol)
        }

        if leaves < 2
        {
            return {width: 0, lastSymbol: 0}
        }

        Slice.sort(nodes[until leaves])
        var symbols: [256] u8
        for index in leaves
        {
            symbols[index] = cast #wrap (u8, nodes[index])
            nodes[index]   >>= 8
        }

        // The sorted leaves and the newly merged branches are two ordered queues.
        var parents: [511] u16
        var leafAt   = 0_u32
        var branchAt = leaves
        var count    = leaves
        while count < leaves * 2 - 1
        {
            let left  = takeNode(&nodes[0], leaves, count, &leafAt, &branchAt)
            let right = takeNode(&nodes[0], leaves, count, &leafAt, &branchAt)
            nodes[count]   = nodes[left] + nodes[right]
            parents[left]  = cast(u16, count)
            parents[right] = cast(u16, count)
            count          += 1
        }

        var depths: [511] u8
        for index in count - 1
        {
            let node = count - 2 - index
            depths[node] = depths[parents[node]] + 1
        }

        const MaxBits = 11_u32
        const Slots   = 1_u32 << MaxBits
        var countsByLength: [MaxBits + 1] u32
        var width = 0_u32
        var used  = 0_u32
        for index in leaves
        {
            let depth = Math.min(cast(u32, depths[index]), MaxBits)
            countsByLength[depth] += 1
            width = Math.max(width, depth)
            used  += 1_u32 << (MaxBits - depth)
        }

        // Splitting a shorter code and deleting one longest code frees one slot.
        // This restores the prefix sum without changing the number of symbols.
        while used > Slots
        {
            var depth = MaxBits - 1
            while not countsByLength[depth]
            {
                depth -= 1
            }

            countsByLength[depth]     -= 1
            countsByLength[depth + 1] += 2
            countsByLength[MaxBits]   -= 1
            used -= 1
        }

        Memory.clear(&.lengths[0], #sizeof(.lengths))
        var bits = 0_u32
        var leaf = 0_u32
        for index in width
        {
            let depth = width - index
            for countsByLength[depth]
            {
                let symbol = symbols[leaf]
                .lengths[symbol] = cast(u8, depth)
                bits += counts[symbol] * depth
                leaf += 1
            }
        }

        if ((bits + 7) >> 3) + 16 >= input.count
        {
            return {width: 0, lastSymbol: 0}
        }

        var slot = 0_u32
        for bitsInCode in 1 to width
        {
            let bits  = width + 1 - bitsInCode
            let shift = bitsInCode - 1
            for symbol in lastSymbol + 1 where .lengths[symbol] == bits
            {
                .codes[symbol] = cast(u16, slot >> shift)
                slot += 1_u32 << shift
            }
        }

        return {width: width, lastSymbol: lastSymbol}
    }

    private mtd const weight(symbol, width: u32)->u32
    {
        let length = .lengths[symbol]
        return length ? width + 1 - length : 0
    }

    private mtd writeDescription(lastSymbol, width: u32)->bool
    {
        if lastSymbol <= 128
        {
            .encoded.add(cast(u8, 127 + lastSymbol))
            for index in (lastSymbol + 1) >> 1
            {
                let first = index * 2
                let high  = .weight(first, width) << 4
                let low   = first + 1 < lastSymbol ? .weight(first + 1, width) : 0
                .encoded.add(cast(u8, high | low))
            }

            return true
        }

        .encoded.add(0)
        var probabilities: ReverseWriter
        probabilities.write(&.encoded, 1, 4)
        var remaining = 65_u32
        var threshold = 64_u32
        var count     = 7_u32
        for frequency in WeightDistribution
        {
            let actual  = cast(u32, frequency) + 1
            let maximum = 2 * threshold - 1 - remaining
            if actual < maximum
            {
                probabilities.write(&.encoded, actual, count - 1)
            }
            else
            {
                let encoded = actual < threshold ? actual : actual + maximum
                probabilities.write(&.encoded, encoded, count)
            }

            remaining -= cast(u32, frequency)
            while remaining < threshold
            {
                threshold >>= 1
                count     -= 1
            }
        }

        probabilities.flush(&.encoded)

        var states:  [2] u32
        var weights: ReverseWriter
        for reverseIndex in lastSymbol
        {
            let symbol = lastSymbol - 1 - reverseIndex
            let lane   = symbol & 1
            let weight = .weight(symbol, width)
            if reverseIndex < 2
            {
                states[lane] = WeightEncoding.first[weight]
            }
            else
            {
                let next  = states[lane]
                let state = WeightEncoding.inverse[weight, next]
                let entry = WeightEncoding.entries[state]
                weights.write(&.encoded, next - entry.base, entry.bits)
                states[lane] = state
            }
        }

        weights.write(&.encoded, states[1], WeightEncoding.log)
        weights.write(&.encoded, states[0], WeightEncoding.log)
        weights.finish(&.encoded)

        let size = .encoded.count - 1
        if size >= 128
        {
            return false
        }

        .encoded[0] = cast(u8, size)
        return true
    }

    private mtd writeStream(input: const [..] u8)
    {
        var writer: ReverseWriter
        for reverseIndex in input.count
        {
            let symbol = input[input.count - 1 - reverseIndex]
            writer.write(&.encoded, .codes[symbol], .lengths[symbol])
        }

        writer.finish(&.encoded)
    }

    mtd write(output: *Array!{u8}, input: const [..] u8)->bool
    {
        let codes = .makeCodes(input)
        if not codes.width
        {
            return false
        }

        .encoded.clear()
        if not .writeDescription(codes.lastSymbol, codes.width)
        {
            return false
        }

        let single = input.count < 256
        if single
        {
            .writeStream(input)
        }
        else
        {
            let segment = (input.count + 3) / 4
            let jump    = .encoded.count
            appendLittle(&.encoded, 0, 6)
            for stream in 4
            {
                let start  = stream * segment
                let end    = Math.min(start + segment, input.count)
                let before = .encoded.count
                .writeStream(input[start until end])
                if stream != 3
                {
                    let size = .encoded.count - before
                    .encoded[jump + stream * 2]     = Math.byteAt(size, 0)
                    .encoded[jump + stream * 2 + 1] = Math.byteAt(size, 1)
                }
            }
        }

        let stored     = .encoded.count
        let headerSize = input.count < 1024 and stored < 1024 ? 3_u32 : input.count < 16384 and stored < 16384 ? 4_u32 : 5_u32
        if stored + headerSize >= input.count
        {
            return false
        }

        let format = headerSize == 3 ? (single ? 0_u64 : 1_u64) : cast(u64, headerSize - 2)
        let width  = 10 + (headerSize - 3) * 4
        let header = (stored << (width + 4)) | (input.count << 4) | (format << 2) | 2
        appendLittle(output, header, headerSize)
        output.add(.encoded.toSlice())
        return true
    }
}
