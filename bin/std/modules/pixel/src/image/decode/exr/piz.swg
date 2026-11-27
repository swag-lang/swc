//! PIZ scanline decompression for OpenEXR.
//! The format uses a reverse canonical Huffman alphabet, a two-dimensional wavelet,
//! and a bitmap of the original 16-bit sample values.

#global namespace Exr

using Core, Core.Errors, Core.Math

const PizCompression = 4_u8

struct PizScratch
{
    lengths: Array!{u8}
    direct:  Array!{u32}
    symbols: Array!{u32}
    palette: Array!{u16}
    samples: Array!{u16}
}

private const PizBitmapBytes = 8192_u64
private const PizWordValues  = 65536_u32
private const PizSignedRange = 16384_u64

private const PizCodeBits   = 6_u32
private const PizCodeMask   = 63_u32
private const PizMaxLength  = 58_u32
private const PizDirectBits = 12_u32

private struct PizBits
{
    source:    const [..] u8
    remaining: u64
    cursor:    u64
    window:    u64
    buffered:  u32
}

private impl PizBits
{
    #[Swag.Inline]
    mtd refill()
    {
        if .buffered > 56
        {
            return
        }

        if .source.count - .cursor >= 8
        {
            let word  = Math.bigEndianToNative(cast(const [*] u64, .source.buffer + .cursor)[0])
            let bytes = (64 - .buffered) >> 3
            .window   |= word >> .buffered
            .cursor   += bytes
            .buffered += bytes * 8
            return
        }

        while .cursor < .source.count and .buffered <= 56
        {
            .window   |= cast(u64, .source[.cursor]) << (56 - .buffered)
            .cursor   += 1
            .buffered += 8
        }
    }

    #[Swag.Inline]
    mtd const peek(width: u32)->u64 => .window >> (64 - width)

    #[Swag.Inline]
    mtd consume(width: u32)
    {
        .window    <<= width
        .remaining -= width
        .buffered  -= width
    }

    #[Swag.Inline]
    mtd read(width: u32)->u32 fail
    {
        if width > .remaining
        {
            fail InvalidFormatError{"OpenEXR PIZ bit stream is truncated"}
        }

        if .buffered < width
        {
            .refill()
        }

        let value = cast(u32, .peek(width))
        .consume(width)
        return value
    }
}

private struct PizHuffman
{
    counts:       [PizMaxLength + 1] u32
    offsets:      [PizMaxLength + 1] u32
    first:        [PizMaxLength + 1] u64
    longest:      u32
    rootBits:     u32
    extendedBits: u32
}

private impl PizHuffman
{
    mtd build(packed: const [..] u8, firstSymbol, repeatSymbol: u32, scratch: *PizScratch) fail
    {
        let alphabet = cast(u64, repeatSymbol - firstSymbol) + 1
        scratch.lengths.resize(alphabet)
        var bits:  PizBits = {source: packed, remaining: packed.count * 8}
        var index: u64
        while index < alphabet
        {
            let entry = try bits.read(PizCodeBits)
            if entry <= PizMaxLength
            {
                scratch.lengths[index] = cast(u8, entry)
                .counts[entry]         += 1
                index += 1
                continue
            }

            // Tags 59–62 stand for two through five unused symbols. Tag 63
            // takes an additional byte and represents six through 261.
            let zeros = entry == 63 ? 6 + try bits.read(8) : entry - 57
            if zeros > alphabet - index
            {
                fail InvalidFormatError{"OpenEXR PIZ code lengths exceed the alphabet"}
            }

            Memory.clear(scratch.lengths.storage() + index, zeros)
            index += zeros
        }

        if bits.remaining >= 8 or not scratch.lengths[alphabet - 1]
        {
            fail InvalidFormatError{"OpenEXR PIZ Huffman table has an invalid length"}
        }

        // In PIZ, the longer codes occupy the numerically smaller prefixes.
        // Fold complete pairs of leaves and occupied prefixes towards the root.
        var parents: u64
        for width in rangeTo(1_u32, PizMaxLength).reversed()
        {
            let total = parents + .counts[width]
            if (total & 1) or total > 1_u64 << width
            {
                fail InvalidFormatError{"OpenEXR PIZ Huffman tree is invalid"}
            }

            if .counts[width] and not .longest
            {
                .longest = width
            }

            .first[width] = parents
            parents       = total >> 1
        }

        if parents != 1
        {
            fail InvalidFormatError{"OpenEXR PIZ Huffman tree is incomplete"}
        }

        .rootBits     = Math.min(.longest, PizDirectBits)
        .extendedBits = Math.min(.longest, .rootBits + 4)
        let rootEntries = 1_u64 << .rootBits

        // Only the numerically lowest root prefixes are occupied by longer codes.
        let extensions = .first[.rootBits] << (.extendedBits - .rootBits)
        scratch.direct.resize(rootEntries + extensions)
        if extensions
        {
            Memory.clear(scratch.direct.storage(), scratch.direct.count * #sizeof(u32))
        }

        if .longest > .extendedBits
        {
            var longCount: u32
            for width in .extendedBits + 1 to .longest
            {
                .offsets[width] = longCount
                longCount       += .counts[width]
            }

            scratch.symbols.resize(longCount)
        }

        var next: [PizMaxLength + 1] u32
        for width, symbolIndex in scratch.lengths
        {
            if not width
            {
                continue
            }

            let symbol  = firstSymbol + cast(u32, symbolIndex)
            let ordinal = next[width]
            next[width] += 1
            if width <= .extendedBits
            {
                let extended = width > .rootBits
                let shift    = (extended ? .extendedBits : .rootBits) - width
                let begin    = (extended ? rootEntries : 0) + ((.first[width] + ordinal) << shift)
                let entry    = (symbol << PizCodeBits) | width
                for slot in begin until begin + (1_u64 << shift)
                {
                    scratch.direct[slot] = entry
                }
            }
            else
            {
                scratch.symbols[.offsets[width] + ordinal] = symbol
            }
        }
    }

    #[Swag.Inline]
    mtd const readLong(bits: *PizBits, symbols: const [..] u32)->u32 fail
    {
        if bits.buffered < .longest
        {
            bits.refill()
        }

        let available = Math.min(cast(u64, .longest), bits.remaining)
        let cached    = cast(u32, Math.min(available, cast(u64, bits.buffered)))
        for width in .extendedBits + 1 to cached
        {
            let index = bits.peek(width)
            let first = .first[width]
            if index >= first and index - first < .counts[width]
            {
                bits.consume(width)
                return symbols[.offsets[width] + index - first]
            }
        }

        // A byte-aligned refill may leave only 57 bits before a 58-bit code.
        // Read the final bits without shifting past the buffered window.
        if cached < available
        {
            var index = bits.peek(cached)
            bits.consume(cached)
            for width in cached + 1 to cast(u32, available)
            {
                index = (index << 1) | try bits.read(1)
                let first = .first[width]
                if index >= first and index - first < .counts[width]
                {
                    return symbols[.offsets[width] + index - first]
                }
            }
        }

        fail InvalidFormatError{"OpenEXR PIZ Huffman symbol is invalid"}
    }
}

private func decodePizHuffman(packed: const [..] u8, output: [..] u16, scratch: *PizScratch) fail
{
    if packed.count < 20
    {
        fail InvalidFormatError{"OpenEXR PIZ Huffman header is truncated"}
    }

    let firstSymbol  = readU32(packed.buffer)
    let repeatSymbol = readU32(packed.buffer + 4)
    let tableBytes   = cast(u64, readU32(packed.buffer + 8))
    let payloadBits  = cast(u64, readU32(packed.buffer + 12))
    let payloadBytes = (payloadBits + 7) >> 3
    if firstSymbol >= repeatSymbol or
       repeatSymbol > PizWordValues or
       tableBytes + payloadBytes != packed.count - 20
    {
        fail InvalidFormatError{"OpenEXR PIZ Huffman header is invalid"}
    }

    let dataStart = 20 + tableBytes
    var table: PizHuffman
    try table.build(packed[20 until dataStart], firstSymbol, repeatSymbol, scratch)
    var bits:  PizBits = {source: packed[dataStart until packed.count], remaining: payloadBits}
    var index: u64
    while bits.remaining
    {
        if bits.buffered < table.rootBits
        {
            bits.refill()
        }

        var entry = scratch.direct[bits.peek(table.rootBits)]
        if not entry and table.extendedBits > table.rootBits
        {
            if bits.buffered < table.extendedBits
            {
                bits.refill()
            }

            entry = scratch.direct[(1_u64 << table.rootBits) + bits.peek(table.extendedBits)]
        }

        var symbol: u32
        if entry
        {
            let length = entry & PizCodeMask
            if length > bits.remaining
            {
                fail InvalidFormatError{"OpenEXR PIZ Huffman symbol is truncated"}
            }

            bits.consume(length)
            symbol = entry >> PizCodeBits
        }
        else
        {
            symbol = try table.readLong(&bits, scratch.symbols.toSlice())
        }

        if symbol == repeatSymbol
        {
            let run = try bits.read(8)
            if not index or run > output.count - index
            {
                fail InvalidFormatError{"OpenEXR PIZ repeat exceeds the output"}
            }

            let sample = output[index - 1]
            for slot in index until index + run
            {
                output[slot] = sample
            }

            index += run
        }
        else
        {
            if index == output.count
            {
                fail InvalidFormatError{"OpenEXR PIZ Huffman output is too large"}
            }

            output[index] = cast(u16, symbol)
            index         += 1
        }
    }

    if index != output.count
    {
        fail InvalidFormatError{"OpenEXR PIZ Huffman output is incomplete"}
    }
}

#[Swag.Inline]
private func(FullRange: bool) pizWaveletPair(low, high: u16)->[2] u16
{
    #static if FullRange
    {
        // The full-range basis inverts in modulo-65536 arithmetic.
        let b = low - #wrap (high >> 1)
        return [high + #wrap b - #wrap 0x8000_u16, b]
    }
    else
    {
        let average    = cast(s32, cast #bit(s16, low))
        let difference = cast(s32, cast #bit(s16, high))
        let a          = average + (difference >> 1) + (difference & 1)
        return [cast(u16, a & 0xFFFF), cast(u16, (a - difference) & 0xFFFF)]
    }
}

#[Swag.Inline]
private func(FullRange: bool) pizWaveletVectors(low, high: Simd.U16x8)->[2] Simd.U16x8
{
    #static if FullRange
    {
        let b = low - (high >> 1)
        return [high + b - 0x8000_u16, b]
    }
    else
    {
        let signed = cast #bit(Simd.S16x8, high)
        let a      = low + cast #bit(Simd.U16x8, signed >> 1) + (high & 1_u16)
        return [a, a - high]
    }
}

#[Swag.Inline]
private func(FullRange: bool, Lane) writeFinePizWaveletRow(target: [*] u16, first, second: Simd.U16x8)
{
    // A 32-bit lane holds both words of a FLOAT sample so they stay together
    // through the horizontal permutation. The arithmetic remains word-sized.
    let left  = cast #bit(Lane, first)
    let right = cast #bit(Lane, second)
    let low   = cast #bit(Simd.U16x8, Simd.deinterleaveEven(left, right))
    let high  = cast #bit(Simd.U16x8, Simd.deinterleaveOdd(left, right))
    let pair  = pizWaveletVectors!{FullRange}(low, high)
    let even  = cast #bit(Lane, pair[0])
    let odd   = cast #bit(Lane, pair[1])
    Simd.store(target, cast #bit(Simd.U16x8, Simd.interleaveLow(even, odd)))
    Simd.store(target + 8, cast #bit(Simd.U16x8, Simd.interleaveHigh(even, odd)))
}

private func(FullRange: bool, SampleWords: u64) undoPizWavelet(samples: [*] u16, width, rows: u64)
{
    let rowStride = width * SampleWords
    let limit     = Math.min(width, rows)
    var step      = 1_u64
    while step * 2 <= limit
    {
        step *= 2
    }

    step >>= 1
    while step
    {
        let span  = step * 2
        let right = step * SampleWords
        let down  = step * rowStride
        var y: u64
        while rows - y >= span
        {
            let top = samples + y * rowStride
            var x: u64
            if step == 1
            {
                const VectorPixels = 16 / SampleWords
                while width - x >= VectorPixels
                {
                    let a      = top + x * SampleWords
                    let b      = a + down
                    let first  = pizWaveletVectors!{FullRange}(Simd.load(a), Simd.load(b))
                    let second = pizWaveletVectors!{FullRange}(Simd.load(a + 8), Simd.load(b + 8))
                    #static if SampleWords == 1
                    {
                        writeFinePizWaveletRow!{FullRange, Simd.U16x8}(a, first[0], second[0])
                        writeFinePizWaveletRow!{FullRange, Simd.U16x8}(b, first[1], second[1])
                    }
                    else
                    {
                        writeFinePizWaveletRow!{FullRange, Simd.U32x4}(a, first[0], second[0])
                        writeFinePizWaveletRow!{FullRange, Simd.U32x4}(b, first[1], second[1])
                    }

                    x += VectorPixels
                }
            }

            while width - x >= span
            {
                for component in SampleWords
                {
                    let p = top + x * SampleWords + component
                    let l = pizWaveletPair!{FullRange}(p[0], p[down])
                    let r = pizWaveletPair!{FullRange}(p[right], p[down + right])
                    let a = pizWaveletPair!{FullRange}(l[0], r[0])
                    let b = pizWaveletPair!{FullRange}(l[1], r[1])
                    p[0]            = a[0]
                    p[right]        = a[1]
                    p[down]         = b[0]
                    p[down + right] = b[1]
                }

                x += span
            }

            if width & step
            {
                for component in SampleWords
                {
                    let p    = top + x * SampleWords + component
                    let pair = pizWaveletPair!{FullRange}(p[0], p[down])
                    p[0]    = pair[0]
                    p[down] = pair[1]
                }
            }

            y += span
        }

        if rows & step
        {
            let top = samples + y * rowStride
            var x: u64
            while width - x >= span
            {
                for component in SampleWords
                {
                    let p    = top + x * SampleWords + component
                    let pair = pizWaveletPair!{FullRange}(p[0], p[right])
                    p[0]     = pair[0]
                    p[right] = pair[1]
                }

                x += span
            }
        }

        step >>= 1
    }
}

private func(FullRange: bool) undoPizChannel(samples: [*] u16, width, rows, sampleWords: u64)
{
    if sampleWords == 1
    {
        undoPizWavelet!{FullRange, 1}(samples, width, rows)
    }
    else
    {
        undoPizWavelet!{FullRange, 2}(samples, width, rows)
    }
}

func decodePizScanlines(packed: const [..] u8, expected, width, rows: u64, channels: const [..] Channel, scratch: *PizScratch, output: *Array!{u8}) fail
{
    if packed.count < 8
    {
        fail InvalidFormatError{"OpenEXR PIZ header is truncated"}
    }

    let firstByte   = cast(u64, readU16(packed.buffer))
    let lastByte    = cast(u64, readU16(packed.buffer + 2))
    let bitmapBytes = firstByte <= lastByte ? lastByte - firstByte + 1 : 0
    if lastByte >= PizBitmapBytes or bitmapBytes > packed.count - 8
    {
        fail InvalidFormatError{"OpenEXR PIZ range bitmap is invalid"}
    }

    let huffmanStart = 8 + bitmapBytes
    let huffmanBytes = readU32(packed.buffer + 4 + bitmapBytes)
    if huffmanBytes != packed.count - huffmanStart
    {
        fail InvalidFormatError{"OpenEXR PIZ Huffman data has an invalid size"}
    }

    scratch.palette.clear()
    scratch.palette.reserve(Math.min(cast(u64, PizWordValues), bitmapBytes * 8 + 1))
    scratch.palette.add(0)
    for byteIndex in bitmapBytes
    {
        let base = (firstByte + byteIndex) * 8
        var mask = cast(u32, packed[4 + byteIndex])
        if not base
        {
            mask &= 254
        }

        while mask
        {
            scratch.palette.add(cast(u16, base + Math.trailingZeros(mask)))
            mask &= mask - 1
        }
    }

    scratch.samples.resize(expected / 2)
    try decodePizHuffman(packed[huffmanStart until packed.count], scratch.samples.toSlice(), scratch)
    let samples = scratch.samples.storage()
    var planeOffset: u64
    for channel in channels
    {
        let words = channel.pixelType == 1 ? 1_u64 : 2_u64
        let plane = samples + planeOffset
        if scratch.palette.count > PizSignedRange
        {
            undoPizChannel!{true}(plane, width, rows, words)
        }
        else
        {
            undoPizChannel!{false}(plane, width, rows, words)
        }

        planeOffset += width * rows * words
    }

    // PIZ stores each channel for the whole block. Restore the file's per-row
    // channel order and expand the palette indices in the same pass.
    output.resize(expected)
    let target = cast([*] u16, output.storage())
    var written: u64
    for row in rows
    {
        planeOffset = 0
        for channel in channels
        {
            let rowWords = width * (channel.pixelType == 1 ? 1 : 2)
            let source   = samples + planeOffset + row * rowWords
            for word in rowWords
            {
                let index = source[word]
                if index >= scratch.palette.count
                {
                    fail InvalidFormatError{"OpenEXR PIZ sample lies outside the range bitmap"}
                }

                target[written + word] = Math.nativeToLittleEndian(scratch.palette[index])
            }

            planeOffset += rowWords * rows
            written     += rowWords
        }
    }
}
