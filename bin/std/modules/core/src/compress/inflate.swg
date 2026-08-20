/*
    :LICENCE
    This code is based on the Odin library (https://github.com/odin-lang/Odin/blob/master/core/compress/zlib/zlib.odin)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Compress

using Core.Errors

internal
{
    const FastBits        = 9
    const FastMask        = (1 << FastBits) - 1
    const HuffmanMaxBits  = 16
    const HuffmanFastBits = 9

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

    struct HuffmanTable
    {
        fast:        [1 << FastBits] u16     // Fast associated with this value.
        firstCode:   [16] u16                // First code associated with this value.
        maxCode:     [17] s64                // Max code associated with this value.
        firstSymbol: [16] u16                // First symbol associated with this value.
        size:        [288] u8                // Size associated with this value.
        value:       [288] u16               // Value associated with this value.
    }

    impl HuffmanTable
    {
        mtd init(codeLengths: const [..] u8) fail
        {
            var sizes:    [HuffmanMaxBits + 1] u16
            var nextCode: [HuffmanMaxBits] u16

            @init(me, 1)
            for v in codeLengths do
                sizes[v] += 1
            sizes[0] = 0

            for i in 1 to 16
            {
                if cast(u32) sizes[i] > (1'u32 << i) do
                    fail InvalidFormatError{"bad huffman sizes"}
            }

            var k   = 0'u16
            var cde = 0'u32
            for i in 1 to 15
            {
                nextCode[i]     = cast(u16) cde
                .firstCode[i]   = cast(u16) cde
                .firstSymbol[i] = k
                cde             += sizes[i]
                if sizes[i] != 0 and (cast(u32) cde - 1) >= (1'u32 << i) do
                    fail InvalidFormatError{"huffman bad code lengths"}
                .maxCode[i] = cast(s64) cde << (16 - i)
                cde         <<= 1
                k           += sizes[i]
            }

            .maxCode[16] = 0x10000
            for v, ci in codeLengths
            {
                if !v do
                    continue

                let c     = nextCode[v] - .firstCode[v] + .firstSymbol[v]
                let fastv = (cast(u16) v << 9) | cast(u16) ci
                .size[c]  = v
                .value[c] = cast(u16) ci
                if v <= FastBits
                {
                    var j = reverse16(nextCode[v], v)
                    while j < (1 << FastBits)
                    {
                        .fast[j] = fastv
                        j        += (1'u16 << v)
                    }
                }

                nextCode[v] += 1
            }
        }
    }
}

// Represents inflate.
#[Swag.Opaque]
public struct Inflate
{
    // Size of the back-reference window, fixed for the duration of one 'decompress' call.
    private windowSize: u32

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
    // Defines inflate max distance.
    public const InflateMaxDistance = 32768'u32

    mtd decode(ht: *HuffmanTable)->u16 fail
    {
        if .stream.numBits < 16
        {
            .stream.refill()
            if .stream.numBits == 255 do
                fail InvalidFormatError{"malformed"}
        }

        let b = ht.fast[.stream.codeBuffer & FastMask]
        if b
        {
            let s = cast(u8) (b >> FastBits)
            .stream.consumeBits(s)
            return b & 511
        }

        let cde = cast(u16) .stream.peekBits(16)
        let k   = reverse16(cde, 16)

        var s = HuffmanFastBits + 1
        while k >= ht.maxCode[s] do
            s += 1

        if s >= 16 do
            fail InvalidFormatError{"bad huffman code"}
        let b1 = (k >> (16 - s)) - ht.firstCode[s] + ht.firstSymbol[s]
        if b1 >= @countof(ht.size) do
            fail InvalidFormatError{"bad huffman code"}
        if ht.size[b1] != s do
            fail InvalidFormatError{"bad huffman code"}

        .stream.consumeBits(cast(u8) s)
        return ht.value[b1]
    }

    // Decodes one deflate block into 'dest'.
    //
    // A stream that does not compress spends this loop once per output byte — a
    // screen grab of a photograph runs it fifteen million times for seventeen
    // megabytes — so both cursors live in locals for the whole block. Reaching
    // through 'me' for the bit cursor and through 'dest' for the output cursor on
    // every symbol is what the loop cannot afford; 'me' and 'dest' are resynced
    // whenever anything else has to see them.
    mtd parseBlock(repeatHt, repeatZ: *HuffmanTable, dest: *Array'u8) fail
    {
        let startBufCount = dest.count

        var cb  = .stream.codeBuffer
        var nb  = cast(u32) .stream.numBits
        var cur = .stream.curByte

        let src  = @dataof(.stream.stream)
        let srcN = @countof(.stream.stream)

        // Highest cursor from which an eight-byte load stays in bounds, expressed as
        // an exclusive bound so a source shorter than eight bytes simply has none.
        let fastLimit = srcN >= 8 ? srcN - 7 : 0

        var count = dest.count
        var buf   = dest.buffer
        var cap   = dest.capacity

        // The refill below assumes at most 63 buffered bits: with 64 its byte advance
        // would underflow. Hand the top byte back to the source to get there.
        if nb >= 64
        {
            cb  &= 0x00FFFFFFFFFFFFFF
            nb  -= 8
            cur -= 1
        }

        for
        {
            // Refill to at least 56 bits with one unaligned 64-bit load, no branch and
            // no masking. The bits left above 'nb' are the source bits that follow, so
            // the next refill ORs the very same values back over them; every consumer
            // masks what it peeks, and 'nb' never drops below 48 inside one iteration.
            if cur < fastLimit
            {
                cb  |= (src! + cur)[as u64] << #wrap nb
                cur += cast(u64) ((63 - nb) >> 3)
                nb  |= 56
            }
            elif nb <= 56
            {
                // The byte-wise refill ORs into the buffer, so it needs the stricter
                // "nothing above numBits" invariant back before it runs.
                if nb != 64 do
                    cb &= (1'u64 << nb) - 1
                .stream.codeBuffer = cb
                .stream.numBits    = cast(u8) nb
                .stream.curByte    = cur
                .stream.refill(56)
                if .stream.numBits == 255 do
                    fail InvalidFormatError{"malformed"}
                cb  = .stream.codeBuffer
                nb  = cast(u32) .stream.numBits
                cur = .stream.curByte
            }

            var value: u32
            let b = repeatHt.fast[cb & FastMask]
            if b
            {
                let s = cast(u32) (b >> FastBits)
                cb    >>= s
                nb    -= s
                value = b & 511
            }
            else
            {
                let k = reverse16(cast(u16) (cb & 0xFFFF), 16)
                var s = HuffmanFastBits + 1
                while k >= repeatHt.maxCode[s] do
                    s += 1
                if s >= 16 do
                    fail InvalidFormatError{"bad huffman code"}
                let b1 = (k >> (16 - s)) - repeatHt.firstCode[s] + repeatHt.firstSymbol[s]
                if b1 >= @countof(repeatHt.size) do
                    fail InvalidFormatError{"bad huffman code"}
                if repeatHt.size[b1] != s do
                    fail InvalidFormatError{"bad huffman code"}
                cb    >>= s
                nb    -= cast(u32) s
                value = repeatHt.value[b1]
            }

            if value < 256
            {
                if count >= cap
                {
                    dest.count = count
                    dest.grow(count + 1)
                    buf = dest.buffer
                    cap = dest.capacity
                }

                let obuf = buf!
                obuf[count] = cast(u8) value
                count       += 1
                continue
            }

            if value == 256
            {
                if nb != 64 do
                    cb &= (1'u64 << nb) - 1
                .stream.codeBuffer = cb
                .stream.numBits    = cast(u8) nb
                .stream.curByte    = cur
                dest.count         = count

                let newSlice = @mkslice(dest.buffer + startBufCount, count - startBufCount)
                .adler.update(newSlice)
                return
            }

            value -= 257
            var length = cast(u64) LengthBase[value]
            let lextra = cast(u32) LengthExtra[value]
            if lextra
            {
                length += cb & ((1'u64 << lextra) - 1)
                cb     >>= lextra
                nb     -= lextra
            }

            var dvalue: u32
            let d = repeatZ.fast[cb & FastMask]
            if d
            {
                let s = cast(u32) (d >> FastBits)
                cb     >>= s
                nb     -= s
                dvalue = d & 511
            }
            else
            {
                let k = reverse16(cast(u16) (cb & 0xFFFF), 16)
                var s = HuffmanFastBits + 1
                while k >= repeatZ.maxCode[s] do
                    s += 1
                if s >= 16 do
                    fail InvalidFormatError{"bad huffman code"}
                let b1 = (k >> (16 - s)) - repeatZ.firstCode[s] + repeatZ.firstSymbol[s]
                if b1 >= @countof(repeatZ.size) do
                    fail InvalidFormatError{"bad huffman code"}
                if repeatZ.size[b1] != s do
                    fail InvalidFormatError{"bad huffman code"}
                cb     >>= s
                nb     -= cast(u32) s
                dvalue = repeatZ.value[b1]
            }

            var distance = cast(u64) DistBase[dvalue]
            let dextra   = cast(u32) DistExtra[dvalue]
            if dextra
            {
                distance += cb & ((1'u64 << dextra) - 1)
                cb       >>= dextra
                nb       -= dextra
            }

            if count < distance do
                fail InvalidFormatError{"bad distance"}
            if !length do
                continue

            // One vector of slack past the match lets the copy below run in whole
            // blocks and overshoot the last one; the overshoot is inside the buffer
            // and the next symbol overwrites it.
            if count + length + #sizeof(Math.Simd.U8x16) > cap
            {
                dest.count = count
                dest.grow(count + length + #sizeof(Math.Simd.U8x16))
                buf = dest.buffer
                cap = dest.capacity
            }

            let obuf = buf!
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
            elif distance >= 8
            {
                // Non-overlapping in eight-byte steps. The source aliases the output,
                // which is why this is a raw word copy rather than 'dest.add(slice)':
                // that path sees the aliasing and allocates a temporary per match.
                let end = count + length
                var dst = count
                while dst < end
                {
                    (obuf + dst)[as u64] = (obuf + from)[as u64]
                    dst                  += 8
                    from                 += 8
                }

                count = end
            }
            elif distance == 1
            {
                Memory.set(obuf + count, obuf[count - 1], length)
                count += length
            }
            else
            {
                // Overlapping: copy forward one byte at a time so each byte reads
                // output the loop has already written.
                for i in length
                {
                    obuf[count] = obuf[from]
                    count       += 1
                    from        += 1
                }
            }
        }
    }

    // Decompress the associated stream
    public mtd decompress(result: *Array'u8, buf: const [..] u8, winSize: u32 = InflateMaxDistance) fail
    {
        .stream.reset(buf)
        .adler.reset()
        .windowSize = Math.min(winSize, InflateMaxDistance)

        var repeatHt:     HuffmanTable
        var repeatZ:      HuffmanTable
        var codeLengthHt: HuffmanTable

        Debug.assert(.windowSize > 0)

        for
        {
            let final = .stream.readBits(1)
            let type  = .stream.readBits(2)

            switch type
            {
            case 0:
                .stream.discardToNextByte()
                let uncompressedLen = cast(u16) .stream.readBits(16)
                let lengthCheck     = cast(u16) .stream.readBits(16)
                if ~uncompressedLen != lengthCheck do
                    fail InvalidFormatError{"invalid buffer, length mismatch"}

                .stream.revert()
                let newSlice = @mkslice(.stream.currentPointer(), uncompressedLen)
                .adler.update(newSlice)
                result.add(newSlice)
                .stream.advanceBytes(uncompressedLen)

            case 1:
                repeatHt.init(FixedLength)
                repeatZ.init(FixedDist)
                .parseBlock(&repeatHt, &repeatZ, result)

            case 3:
                fail InvalidFormatError{"invalid block type"}

            default:
                var lenCodes:        [286 + 32 + 137] u8
                var codeLengthSizes: [19] u8
                .stream.refill(14)
                let hlit  = .stream.readBitsUnchecked(5) + 257
                let hdist = .stream.readBitsUnchecked(5) + 1
                let hclen = .stream.readBitsUnchecked(4) + 4
                for i in hclen
                {
                    let s = cast(u8) .stream.readBits(3)
                    codeLengthSizes[LengthDezigzag[i]] = s
                }

                codeLengthHt.init(codeLengthSizes)
                let ntot = hlit + hdist
                var n    = 0
                while n < ntot
                {
                    var c = .decode(&codeLengthHt)
                    if c < 0 or c >= 19 do
                        fail InvalidFormatError{"bad code lengths"}

                    if c < 16
                    {
                        lenCodes[n] = cast(u8) c
                        n           += 1
                    }
                    else
                    {
                        var fill = 0'u8
                        .stream.refill(7)
                        switch c
                        {
                        case 16:
                            c = cast(u16) (.stream.readBitsUnchecked(2) + 3)
                            if n == 0 do
                                fail InvalidFormatError{"bad code lengths"}
                            fill = lenCodes[n - 1]

                        case 17:
                            c = cast(u16) (.stream.readBitsUnchecked(3) + 3)

                        case 18:
                            c = cast(u16) (.stream.readBitsUnchecked(7) + 11)

                        default:
                            fail InvalidFormatError{"bad code lengths"}
                        }

                        if ntot - n < c do
                            fail InvalidFormatError{"bad code lengths"}
                        let nc = n + c
                        while n < nc
                        {
                            lenCodes[n] = fill
                            n           += 1
                        }
                    }
                }

                if n != ntot do
                    fail InvalidFormatError{"bad code lengths"}
                repeatHt.init(lenCodes[0 to hlit - 1])
                repeatZ.init(lenCodes[hlit to ntot - 1])
                .parseBlock(&repeatHt, &repeatZ, result)
            }

            if final == 1 do
                break
        }
    }
}
