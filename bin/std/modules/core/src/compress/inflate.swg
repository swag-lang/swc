// @LICENCE: Zlib
// @ORIGIN: Odin, https://github.com/odin-lang/Odin/tree/master/core/compress/zlib
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#odin

#global namespace Compress

using Core.Errors

internal
{
    // Literals benefit from a wider direct lookup. Distance tables have fewer
    // symbols, and the code-length alphabet never declares more than seven bits.
    const SymbolBits          = 9
    const SymbolMask          = 0x1FF_u16
    const NarrowLiteralBits   = 9_u32
    const WideLiteralBits     = 11_u32
    const MinWideLiteralBytes = 1024
    const DistanceBits        = 8_u32
    const CodeLengthBits      = 7_u32
    const DistanceMask        = (1 << DistanceBits) - 1
    const CodeLengthMask      = (1 << CodeLengthBits) - 1
    const HuffmanMaxBits      = 16

    // Repeat the final distance bytes of the previous eight output bytes.
    const ShortMatchMasks = #run
    {
        var masks: [6] Math.Simd.U8x16
        for index in 6
        {
            let distance = index + 2
            var lanes: [16] u8
            for lane in 16
            {
                lanes[lane] = cast(u8, (8 - distance + lane % distance))
            }

            masks[index] = cast(Math.Simd.U8x16, lanes)
        }

        return masks
    }

    // Largest number of whole repetitions that one vector can contain.
    const ShortMatchSteps = [16_u64, 15, 16, 15, 12, 14]

    const LengthBase: [31] u16 = [
        3, 4, 5, 6, 7, 8, 9, 10,
        11, 13, 15, 17, 19, 23, 27,
        31, 35, 43, 51, 59, 67, 83,
        99, 115, 131, 163, 195, 227, 258,
        0, 0]

    const LengthExtra: [31] u8 = [
        0, 0, 0, 0, 0, 0, 0, 0,
        1, 1, 1, 1,
        2, 2, 2, 2,
        3, 3, 3, 3,
        4, 4, 4, 4,
        5, 5, 5, 5, 0, 0, 0]

    const LengthDezigzag: [?] u8 = [
        16, 17, 18, 0,
        8, 7, 9, 6, 10,
        5, 11, 4, 12, 3,
        13, 2, 14, 1, 15]

    const DistBase: [32] u16 = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577, 0, 0]

    const DistExtra: [32] u8 = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 0, 0]

    const FixedLength: [288] u8 = [
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
        8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
        9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
        9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
        9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9,
        7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8]

    const FixedDist: [32] u8 = [
        5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]

    #[Swag.Inline]
    func reverse16(n: u16, bits: u8)->u16
    {
        var r = Math.reverse(n)
        r >>= 16 - bits
        return r
    }

    struct(RootBits: u32) HuffmanTable
    {
        fast:        [1 << RootBits] u16     // Direct lookup of codes up to 'RootBits' long: code length << SymbolBits | symbol, or 0.
        firstCode:   [16] u16      // First canonical code of each code length.
        maxCode:     [17] s64      // Exclusive upper bound of the codes of each length, left-aligned to 16 bits.
        firstSymbol: [16] u16      // Slot in 'size' and 'value' of the first code of each length.
        size:        [288] u8      // Code length of each slot, in canonical order.
        value:       [288] u16     // Symbol of each slot, in canonical order.
    }

    impl HuffmanTable
    {
        mtd init(codeLengths: const [..] u8) fail
        {
            var sizes:    [HuffmanMaxBits + 1] u16
            var nextCode: [HuffmanMaxBits] u16

            Swag.init(me, 1)
            for v in codeLengths
            {
                sizes[v] += 1
            }

            sizes[0] = 0

            for i in 1 to 16
            {
                if cast(u32, sizes[i]) > (1_u32 << i)
                {
                    fail InvalidFormatError{"bad huffman sizes"}
                }
            }

            var k   = 0_u16
            var cde = 0_u32
            for i in 1 to 15
            {
                nextCode[i]     = cast(u16, cde)
                .firstCode[i]   = cast(u16, cde)
                .firstSymbol[i] = k
                cde             += sizes[i]
                if sizes[i] != 0 and (cast(u32, cde) - 1) >= (1_u32 << i)
                {
                    fail InvalidFormatError{"huffman bad code lengths"}
                }

                .maxCode[i] = cast(s64, cde) << (16 - i)
                cde         <<= 1
                k           += sizes[i]
            }

            .maxCode[16] = 0x10000
            for v, ci in codeLengths
            {
                if not v
                {
                    continue
                }

                let c     = nextCode[v] - .firstCode[v] + .firstSymbol[v]
                let fastv = (cast(u16, v) << SymbolBits) | cast(u16, ci)
                .size[c]  = v
                .value[c] = cast(u16, ci)
                if v <= RootBits
                {
                    var j = reverse16(nextCode[v], v)
                    while j < (1 << RootBits)
                    {
                        .fast[j] = fastv
                        j        += (1_u16 << v)
                    }
                }

                nextCode[v] += 1
            }
        }
    }
}

private
{
    // RFC 1951 fixes these Huffman trees for every stream and every fixed block.
    var fixedLiteralLengthTable = #run
    {
        var table: HuffmanTable!{NarrowLiteralBits}
        expect table.init(FixedLength)
        return table
    }

    var fixedDistanceTable = #run
    {
        var table: HuffmanTable!{DistanceBits}
        expect table.init(FixedDist)
        return table
    }
}

// Decompresses data in the raw Deflate format (RFC 1951).
//
// Use [[Core.Compress.ZLib]] for a zlib stream, which wraps Deflate data with a header and a
// checksum. One `Inflate` can decompress several inputs in turn.
#[Swag.Opaque]
public struct Inflate
{
    // Size of the back-reference window, fixed for the duration of one 'decompress' call.
    private windowSize: u32

    // Maximum number of bytes that this call may append to the destination.
    private outputLimit: u64
    private outputStart: u64

    // Input cursor and running checksum. The container formats built on top of Inflate read
    // them to parse their own trailer once the compressed block is consumed.

    internal
    {
        stream: BitStream        // Bit cursor over the compressed input.
        adler:  Hash.Adler32     // Adler-32 checksum calculator.
    }
}

impl Inflate
{
    // Largest back-reference distance of the Deflate format, in bytes.
    public const MaxDistance = 32768_u32

    // The header alphabet uses codes of at most seven bits. A single lookup always settles
    // the symbol, and at most seven more bits specify a run of repeated code lengths.
    private mtd readCodeLengths(table: const *HuffmanTable!{CodeLengthBits}, lengths: [..] u8) fail
    {
        const RepeatExtra = [2_u32, 3, 7]
        let source    = unwrap .stream.stream
        let fastLimit = source.count >= 8 ? source.count - 7 : 0
        var buffer    = .stream.codeBuffer
        var bits      = cast(u32, .stream.numBits)
        var cursor    = .stream.curByte
        var written: u64
        while written < lengths.count
        {
            if bits < 14
            {
                if cursor < fastLimit
                {
                    let next = Math.littleEndianToNative(cast(const [*] u64, source.buffer + cursor)[0])
                    buffer |= next << #wrap bits
                    cursor += cast(u64, ((63 - bits) >> 3))
                    bits   |= 56
                }
                else
                {
                    .stream.codeBuffer = buffer & ((1_u64 << bits) - 1)
                    .stream.numBits    = cast(u8, bits)
                    .stream.curByte    = cursor
                    .stream.refill(14)
                    if .stream.numBits == 255
                    {
                        fail InvalidFormatError{"malformed"}
                    }

                    buffer = .stream.codeBuffer
                    bits   = cast(u32, .stream.numBits)
                    cursor = .stream.curByte
                }
            }

            let entry = table.fast[buffer & CodeLengthMask]
            if not entry
            {
                fail InvalidFormatError{"bad huffman code"}
            }

            let code     = entry & SymbolMask
            let codeBits = cast(u32, (entry >> SymbolBits))
            if code < 16
            {
                if bits < codeBits
                {
                    fail InvalidFormatError{"truncated input"}
                }

                lengths[written] = cast(u8, code)
                written += 1
                buffer  >>= codeBits
                bits    -= codeBits
                continue
            }

            let extraBits = RepeatExtra[code - 16]
            let totalBits = codeBits + extraBits
            if bits < totalBits
            {
                fail InvalidFormatError{"truncated input"}
            }

            let extra = (buffer >> codeBits) & ((1_u64 << extraBits) - 1)
            let run   = extra + (code == 18 ? 11 : 3)
            if run > lengths.count - written or (code == 16 and not written)
            {
                fail InvalidFormatError{"bad code lengths"}
            }

            let fill = code == 16 ? lengths[written - 1] : 0
            Memory.set(lengths.buffer + written, fill, run)
            written += run
            buffer  >>= totalBits
            bits    -= totalBits
        }

        .stream.codeBuffer = bits == 64 ? buffer : buffer & ((1_u64 << bits) - 1)
        .stream.numBits    = cast(u8, bits)
        .stream.curByte    = cursor
    }

    // Decodes one deflate block into 'dest'.
    //
    // A stream that does not compress spends this loop once per output byte — a
    // screen grab of a photograph runs it fifteen million times for seventeen
    // megabytes — so both cursors live in locals for the whole block. Reaching
    // through 'me' for the bit cursor and through 'dest' for the output cursor on
    // every symbol is what the loop cannot afford; 'me' and 'dest' are resynced
    // whenever anything else has to see them.
    mtd(LiteralBits: u32) parseBlock(repeatHt: const *HuffmanTable!{LiteralBits}, repeatZ: const *HuffmanTable!{DistanceBits}, dest: *Array!{u8}) fail
    {
        const LiteralMask = (1 << LiteralBits) - 1
        let startBufCount = dest.count

        var cb  = .stream.codeBuffer
        var nb  = cast(u32, .stream.numBits)
        var cur = .stream.curByte

        let src  = (.stream.stream).buffer
        let srcN = (.stream.stream).count

        // Highest cursor from which an eight-byte load stays in bounds, expressed as
        // an exclusive bound so a source shorter than eight bytes simply has none.
        let fastLimit = srcN >= 8 ? srcN - 7 : 0

        // Use absolute bounds so a literal needs one comparison for capacity and output budget.
        let windowSize  = cast(u64, .windowSize)
        let outputStart = .outputStart
        let outputEnd   = outputStart + Math.min(.outputLimit, Swag.U64.Max - outputStart)
        var count       = dest.count
        var buf         = dest.buffer
        var cap         = dest.capacity
        var literalEnd  = Math.min(cap, outputEnd)

        // The refill below assumes at most 63 buffered bits: with 64 its byte advance
        // would underflow. Hand the top byte back to the source to get there.
        if nb >= 64
        {
            cb  &= 0x00FFFFFFFFFFFFFF
            nb  -= #wrap 8
            cur -= 1
        }

        for
        {
            // Start the lookup before refilling when all prefix bits are already buffered.
            let bufferedEntry = repeatHt.fast[cb & LiteralMask]
            let hadFullPrefix = nb >= LiteralBits

            // Refill to at least 56 bits with one unaligned load. Bits above nb are
            // from the next partial source byte. Each lookup masks the bits it needs,
            // and the next refill overlays that same byte.
            if cur < fastLimit
            {
                let chunk = Math.littleEndianToNative(cast(const [*] u64, unwrap src + cur)[0])
                cb  |= chunk << #wrap nb
                cur += cast(u64, ((63 - nb) >> 3))
                nb  |= 56
            }
            else if nb > 64
            {
                // Near the end the refill stops with what is left, and the symbols above
                // then consumed more bits than the input holds: the stream is truncated.
                fail InvalidFormatError{"truncated input"}
            }
            else if nb <= 56
            {
                // The byte-wise refill ORs into the buffer, so it needs the stricter
                // "nothing above numBits" invariant back before it runs.
                if nb != 64
                {
                    cb &= (1_u64 << nb) - 1
                }

                .stream.codeBuffer = cb
                .stream.numBits    = cast(u8, nb)
                .stream.curByte    = cur
                .stream.refill(56)
                if .stream.numBits == 255
                {
                    fail InvalidFormatError{"malformed"}
                }

                cb  = .stream.codeBuffer
                nb  = cast(u32, .stream.numBits)
                cur = .stream.curByte
            }

            var value: u32
            let b = hadFullPrefix ? bufferedEntry : repeatHt.fast[cb & LiteralMask]
            if b
            {
                let s = cast(u32, (b >> SymbolBits))
                if nb < s
                {
                    fail InvalidFormatError{"truncated input"}
                }

                cb    >>= s
                nb    -= #wrap s
                value = b & SymbolMask
            }
            else
            {
                let k = reverse16(cast(u16, (cb & 0xFFFF)), 16)
                var s = LiteralBits + 1
                while k >= repeatHt.maxCode[s]
                {
                    s += 1
                }

                if s >= 16
                {
                    fail InvalidFormatError{"bad huffman code"}
                }

                if nb < s
                {
                    fail InvalidFormatError{"truncated input"}
                }

                let b1 = (k >> (16 - s)) - repeatHt.firstCode[s] + repeatHt.firstSymbol[s]
                if b1 >= repeatHt.size.count
                {
                    fail InvalidFormatError{"bad huffman code"}
                }

                if repeatHt.size[b1] != s
                {
                    fail InvalidFormatError{"bad huffman code"}
                }

                cb    >>= s
                nb    -= #wrap cast(u32, s)
                value = repeatHt.value[b1]
            }

            if value < 256
            {
                if count >= literalEnd
                {
                    if count >= outputEnd
                    {
                        fail UnsupportedFormatError{"inflate output exceeds the configured limit"}
                    }

                    dest.count = count
                    dest.grow(count + 1)
                    buf        = dest.buffer
                    cap        = dest.capacity
                    literalEnd = Math.min(cap, outputEnd)
                }

                let obuf = unwrap buf
                obuf[count] = cast(u8, value)
                count       += 1

                #static if LiteralBits == WideLiteralBits
                {
                    // Finish a group of five without revisiting the refill and output checks.
                    if nb >= 4 * LiteralBits and literalEnd - count >= 4
                    {
                        for 4
                        {
                            let next = repeatHt.fast[cb & LiteralMask]
                            if not next or (next & SymbolMask) >= 256
                            {
                                break
                            }

                            let length = cast(u32, (next >> SymbolBits))
                            obuf[count] = cast(u8, (next & 255))
                            count       += 1
                            cb          >>= length
                            nb          -= #wrap length
                        }

                        continue
                    }
                }

                // A short literal can reuse the buffered bits. With LiteralBits available,
                // every occupied entry in the fast table fits in the current window.
                if nb >= LiteralBits and count < literalEnd
                {
                    let next = repeatHt.fast[cb & LiteralMask]
                    if next and (next & SymbolMask) < 256
                    {
                        let length = cast(u32, (next >> SymbolBits))
                        obuf[count] = cast(u8, (next & 255))
                        count       += 1
                        cb          >>= length
                        nb          -= #wrap length
                    }
                }

                continue
            }

            if value == 256
            {
                if nb > 64
                {
                    fail InvalidFormatError{"truncated input"}
                }

                if nb != 64
                {
                    cb &= (1_u64 << nb) - 1
                }

                .stream.codeBuffer = cb
                .stream.numBits    = cast(u8, nb)
                .stream.curByte    = cur
                dest.count         = count

                let newSlice = Swag.makeSlice(dest.buffer + startBufCount, count - startBufCount)
                .adler.update(newSlice)
                return
            }

            value -= 257

            // RFC 1951 reserves literal/length symbols 286 and 287.
            if value >= 29
            {
                fail InvalidFormatError{"bad length"}
            }

            var length = cast(u64, LengthBase[value])
            let lextra = cast(u32, LengthExtra[value])
            if lextra
            {
                if nb < lextra
                {
                    fail InvalidFormatError{"truncated input"}
                }

                length += cb & ((1_u64 << lextra) - 1)
                cb     >>= lextra
                nb     -= #wrap lextra
            }

            var dvalue: u32
            let d = repeatZ.fast[cb & DistanceMask]
            if d
            {
                let s = cast(u32, (d >> SymbolBits))
                if nb < s
                {
                    fail InvalidFormatError{"truncated input"}
                }

                cb     >>= s
                nb     -= #wrap s
                dvalue = d & SymbolMask
            }
            else
            {
                let k = reverse16(cast(u16, (cb & 0xFFFF)), 16)
                var s = DistanceBits + 1
                while k >= repeatZ.maxCode[s]
                {
                    s += 1
                }

                if s >= 16
                {
                    fail InvalidFormatError{"bad huffman code"}
                }

                if nb < s
                {
                    fail InvalidFormatError{"truncated input"}
                }

                let b1 = (k >> (16 - s)) - repeatZ.firstCode[s] + repeatZ.firstSymbol[s]
                if b1 >= repeatZ.size.count
                {
                    fail InvalidFormatError{"bad huffman code"}
                }

                if repeatZ.size[b1] != s
                {
                    fail InvalidFormatError{"bad huffman code"}
                }

                cb     >>= s
                nb     -= #wrap cast(u32, s)
                dvalue = repeatZ.value[b1]
            }

            // RFC 1951 reserves distance symbols 30 and 31.
            if dvalue >= 30
            {
                fail InvalidFormatError{"bad distance"}
            }

            var distance = cast(u64, DistBase[dvalue])
            let dextra   = cast(u32, DistExtra[dvalue])
            if dextra
            {
                if nb < dextra
                {
                    fail InvalidFormatError{"truncated input"}
                }

                distance += cb & ((1_u64 << dextra) - 1)
                cb       >>= dextra
                nb       -= #wrap dextra
            }

            if distance > windowSize
            {
                fail InvalidFormatError{"bad distance"}
            }

            if count - outputStart < distance
            {
                fail InvalidFormatError{"bad distance"}
            }

            if not length
            {
                continue
            }

            if count > outputEnd or length > outputEnd - count
            {
                fail UnsupportedFormatError{"inflate output exceeds the configured limit"}

                // One vector of slack past the match lets the copy below run in whole
                // blocks and overshoot the last one; the overshoot is inside the buffer
                // and the next symbol overwrites it.
            }

            let writable = cap - count
            if length + #sizeof(Math.Simd.U8x16) > writable
            {
                if length <= writable
                {
                    // The last match can fit exactly in a caller's output slice.
                    // Copy forward without touching bytes outside that slice.
                    let obuf = unwrap buf
                    let from = count - distance
                    for index in length
                    {
                        obuf[count + index] = obuf[from + index]
                    }

                    count += length
                    continue
                }

                dest.count = count
                dest.grow(count + length + #sizeof(Math.Simd.U8x16))
                buf        = dest.buffer
                cap        = dest.capacity
                literalEnd = Math.min(cap, outputEnd)
            }

            let obuf = unwrap buf
            var from = count - distance
            if distance >= #sizeof(Math.Simd.U8x16)
            {
                // A distance of at least one vector makes each unaligned load
                // independent of the store paired with it.
                let end = count + length
                var dst = count
                while dst < end
                {
                    Math.Simd.store(obuf + dst, Math.Simd.load(obuf + from))
                    dst  += #sizeof(Math.Simd.U8x16)
                    from += #sizeof(Math.Simd.U8x16)
                }

                count = end
            }
            else if distance >= 8
            {
                // Each eight-byte load finishes before the following store, including when
                // later steps read the bytes produced by this match.
                let end = count + length
                var dst = count
                while dst < end
                {
                    cast([*] u64, obuf + dst)[0] = cast(const [*] u64, obuf + from)[0]
                    dst  += 8
                    from += 8
                }

                count = end
            }
            else if distance == 1
            {
                Memory.set(obuf + count, obuf[count - 1], length)
                count += length
            }
            else if count >= 8
            {
                let seed    = cast(const [*] u64, (obuf + count - 8))[0]
                let window  = cast #bit(Math.Simd.U8x16, Math.Simd.splat(seed))
                let pattern = Math.Simd.shuffle(window, ShortMatchMasks[distance - 2])
                let step    = ShortMatchSteps[distance - 2]
                let end     = count + length
                var dst     = count
                for
                {
                    Math.Simd.store(obuf + dst, pattern)
                    if end - dst <= #sizeof(Math.Simd.U8x16)
                    {
                        break
                    }

                    dst += step
                }

                count = end
            }
            else
            {
                // Overlapping: copy forward one byte at a time so each byte reads
                // output the loop has already written.
                for length
                {
                    obuf[count] = obuf[from]
                    count       += 1
                    from        += 1
                }
            }
        }
    }

    // Dynamic blocks own their tables. Stored and fixed blocks can use the small
    // main decoder frame without initializing dynamic lookup storage.
    #[Swag.NoInline]
    private mtd(LiteralBits: u32) parseDynamicBlock(result: *Array!{u8}) fail
    {
        var repeatHt:        HuffmanTable!{LiteralBits}
        var repeatZ:         HuffmanTable!{DistanceBits}
        var codeLengthHt:    HuffmanTable!{CodeLengthBits}
        var lenCodes:        [286 + 32] u8
        var codeLengthSizes: [19] u8
        .stream.refill(14)
        if .stream.numBits == 255 or .stream.numBits < 14
        {
            fail InvalidFormatError{"truncated input"}
        }

        let hlit  = .stream.readBitsUnchecked(5) + 257
        let hdist = .stream.readBitsUnchecked(5) + 1
        let hclen = .stream.readBitsUnchecked(4) + 4
        if hlit > 286
        {
            fail InvalidFormatError{"invalid code count"}
        }

        for i in hclen
        {
            if .stream.numBits < 3
            {
                .stream.refill(2)
                if .stream.numBits == 255 or .stream.numBits < 3
                {
                    fail InvalidFormatError{"truncated input"}
                }
            }

            let s = cast(u8, .stream.readBitsUnchecked(3))
            codeLengthSizes[LengthDezigzag[i]] = s
        }

        try codeLengthHt.init(codeLengthSizes)
        let ntot = hlit + hdist
        try .readCodeLengths(&codeLengthHt, lenCodes[0 until ntot])
        try repeatHt.init(lenCodes[0 to hlit - 1])
        try repeatZ.init(lenCodes[hlit to ntot - 1])
        try .parseBlock!{LiteralBits}(&repeatHt, &repeatZ, result)
    }

    // Decompresses the Deflate data in `buf` and appends it to `result`.
    //
    // `winSize` is the maximum back-reference distance, clamped to
    // [[Core.Compress.Inflate.MaxDistance]], and must be nonzero. Fails with
    // [[Core.Errors.InvalidFormatError]] for malformed data or a distance beyond that window,
    // and with [[Core.Errors.UnsupportedFormatError]] when the call would append more than
    // `maxOutputSize` bytes.
    public mtd decompress(result: *Array!{u8}, buf: const [..] u8, winSize: u32 = MaxDistance, maxOutputSize: u64 = Swag.U64.Max) fail
    {
        if not winSize
        {
            fail Errors.BadParameterError{"Deflate window size must be nonzero"}
        }

        .stream.reset(buf)
        .adler.reset()
        .windowSize  = Math.min(winSize, MaxDistance)
        .outputLimit = maxOutputSize
        .outputStart = result.count

        for
        {
            .stream.refill(2)
            if .stream.numBits == 255 or .stream.numBits < 3
            {
                fail InvalidFormatError{"truncated input"}
            }

            let final = .stream.readBitsUnchecked(1)
            let type  = .stream.readBitsUnchecked(2)

            switch type
            {
            case 0:
                .stream.discardToNextByte()
                .stream.refill(31)
                if .stream.numBits == 255 or .stream.numBits < 32
                {
                    fail InvalidFormatError{"truncated input"}
                }

                let uncompressedLen = cast(u16, .stream.readBitsUnchecked(16))
                let lengthCheck     = cast(u16, .stream.readBitsUnchecked(16))
                if ~uncompressedLen != lengthCheck
                {
                    fail InvalidFormatError{"invalid buffer, length mismatch"}
                }

                .stream.revert()
                if uncompressedLen > .stream.size() - .stream.curByte
                {
                    fail InvalidFormatError{"stored block is longer than the remaining input"}
                }

                let outputBytes = result.count - .outputStart
                if outputBytes > .outputLimit or uncompressedLen > .outputLimit - outputBytes
                {
                    fail UnsupportedFormatError{"inflate output exceeds the configured limit"}
                }

                let newSlice = Swag.makeSlice(.stream.currentPointer(), uncompressedLen)
                .adler.update(newSlice)
                result.add(newSlice)
                .stream.advanceBytes(uncompressedLen)

            case 1:
                try .parseBlock!{NarrowLiteralBits}(&fixedLiteralLengthTable, &fixedDistanceTable, result)

            case 3:
                fail InvalidFormatError{"invalid block type"}

            default:
                if buf.count >= MinWideLiteralBytes
                {
                    try .parseDynamicBlock!{WideLiteralBits}(result)
                }
                else
                {
                    try .parseDynamicBlock!{NarrowLiteralBits}(result)
                }
            }

            if final == 1
            {
                break
            }
        }
    }
}
