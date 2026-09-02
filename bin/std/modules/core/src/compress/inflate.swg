// @LICENCE: Zlib
// @ORIGIN: Odin, https://github.com/odin-lang/Odin/tree/master/core/compress/zlib
// @MODIFIED: Ported and modified for Swag. The block decoder was rebuilt around a
// libdeflate-style fast loop: packed fast-table entries, literal bursts, and
// pattern-replicated match copies.
// @NOTICE: /bin/THIRDPARTY.md#odin

#global namespace Compress

using Core.Errors

internal
{
    const FastBits        = 12
    const FastMask        = (1 << FastBits) - 1
    const HuffmanMaxBits  = 16
    const HuffmanFastBits = FastBits

    // Packed fast-table entry, one per 'FastBits'-bit window of the bit stream:
    //
    //   bit  31       literal, or plain symbol for a code-length table
    //   bit  30       end-of-block
    //   bits 16..31   literal byte, plain symbol, or length/distance base
    //   bits 8..12    number of extra bits following the code
    //   bits 0..4     number of bits of the code itself
    //
    // A zero entry means the code is longer than 'FastBits' (or invalid) and goes
    // through the canonical first/max-code walk. Distance entries carry a base up
    // to 24577 in the high half and never test the flag bits.
    const EntryLiteral = 0x8000_0000'u32
    const EntryEob     = 0x4000_0000'u32

    // What a table's symbols mean, which decides how its fast entries are packed.
    enum TableKind
    {
        Plain            // Symbols are returned as-is (code-length header table).
        Lengths          // Literal bytes, end-of-block, and match-length symbols.
        Distances        // Match-distance symbols.
    }

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

    // Byte-index patterns replicating a short match period across one vector, and how
    // far one 16-byte store may advance while staying on the period.
    const PatternIndex: [8] Math.Simd.U8x16 = [
        cast(Math.Simd.U8x16) [0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        cast(Math.Simd.U8x16) [0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        cast(Math.Simd.U8x16) [0'u8, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1],
        cast(Math.Simd.U8x16) [0'u8, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0],
        cast(Math.Simd.U8x16) [0'u8, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3, 0, 1, 2, 3],
        cast(Math.Simd.U8x16) [0'u8, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0, 1, 2, 3, 4, 0],
        cast(Math.Simd.U8x16) [0'u8, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1, 2, 3],
        cast(Math.Simd.U8x16) [0'u8, 1, 2, 3, 4, 5, 6, 0, 1, 2, 3, 4, 5, 6, 0, 1]]

    const PatternAdvance: [8] u64 = [16, 16, 16, 15, 16, 15, 12, 14]

    #[Swag.Inline]
    func reverse16(n: u16, bits: u8)->u16
    {
        var r = Math.reverse(n)
        r >>= 16 - bits
        return r
    }

    struct HuffmanTable
    {
        fastEx:      [1 << FastBits] u32     // Packed fast entries (see above).
        firstCode:   [16] u16                // First code associated with this value.
        maxCode:     [17] s64                // Max code associated with this value.
        firstSymbol: [16] u16                // First symbol associated with this value.
        size:        [288] u8                // Size associated with this value.
        value:       [288] u16               // Value associated with this value.
    }

    impl HuffmanTable
    {
        mtd init(codeLengths: const [..] u8, kind: TableKind) fail
        {
            var sizes:    [HuffmanMaxBits + 1] u16
            var nextCode: [HuffmanMaxBits] u16

            Swag.init(me, 1)
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

                let c = nextCode[v] - .firstCode[v] + .firstSymbol[v]
                .size[c]  = v
                .value[c] = cast(u16) ci
                if v <= FastBits
                {
                    // Pack everything a fast decode needs in one entry, so the hot
                    // loop never touches the scalar base/extra tables.
                    var entry = 0'u32
                    switch kind
                    {
                    case .Plain:
                        entry = EntryLiteral | (cast(u32) ci << 16) | v

                    case .Lengths:
                        if ci < 256 do
                            entry = EntryLiteral | (cast(u32) ci << 16) | v
                        elif ci == 256 do
                            entry = EntryEob | v
                        elif ci - 257 < 29 do
                            entry = (cast(u32) LengthBase[ci - 257] << 16) | (cast(u32) LengthExtra[ci - 257] << 8) | v

                    case .Distances:
                        if ci < 30 do
                            entry = (cast(u32) DistBase[ci] << 16) | (cast(u32) DistExtra[ci] << 8) | v
                    }

                    if entry
                    {
                        var j = reverse16(nextCode[v], v)
                        while j < (1 << FastBits)
                        {
                            .fastEx[j] = entry
                            j          += (1'u16 << v)
                        }
                    }
                }

                nextCode[v] += 1
            }
        }
    }

    // Decodes one symbol longer than 'FastBits' with the canonical first/max-code walk.
    func decodeSlow(ht: *HuffmanTable, cb: *u64, nb: *u32)->u16 fail
    {
        let k = reverse16(cast(u16) (cb[] & 0xFFFF), 16)
        var s = HuffmanFastBits + 1
        while k >= ht.maxCode[s] do
            s += 1
        if s >= 16 do
            fail InvalidFormatError{"bad huffman code"}
        let b1 = (k >> (16 - s)) - ht.firstCode[s] + ht.firstSymbol[s]
        if b1 >= ht.size.count do
            fail InvalidFormatError{"bad huffman code"}
        if ht.size[b1] != s do
            fail InvalidFormatError{"bad huffman code"}
        cb[] >>= s
        nb[] -= #wrap cast(u32) s
        return ht.value[b1]
    }
}

// Represents inflate.
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

        let b = ht.fastEx[.stream.codeBuffer & FastMask]
        if b & EntryLiteral
        {
            .stream.consumeBits(cast(u8) (b & 31))
            return cast(u16) ((b >> 16) & 0x1FF)
        }

        var cb = .stream.codeBuffer
        var nb = cast(u32) .stream.numBits
        let v  = decodeSlow(ht, &cb, &nb)
        .stream.codeBuffer = cb
        .stream.numBits    = cast(u8) nb
        return v
    }

    // Decodes one deflate block into 'dest'.
    //
    // A stream that does not compress spends this loop once per output byte — a
    // screen grab of a photograph runs it fifteen million times for seventeen
    // megabytes — so both cursors live in locals for the whole block, and the bulk
    // of the stream runs in a fast loop that checks its bounds once per symbol
    // group: the destination keeps enough slack for a literal burst, a whole match,
    // and a vector overshoot, and every store goes through a raw pointer. The
    // careful loop below it handles the stream tail, growth, rare long codes, and
    // end-of-block, and 'me'/'dest' are resynced whenever anything else must see them.
    mtd parseBlock(repeatHt, repeatZ: *HuffmanTable, dest: *Array'u8) fail
    {
        let startBufCount = dest.count

        var cb  = .stream.codeBuffer
        var nb  = cast(u32) .stream.numBits
        var cur = .stream.curByte

        let src  = (.stream.stream).buffer
        let srcN = (.stream.stream).count

        // Highest cursor from which an eight-byte load stays in bounds, expressed as
        // an exclusive bound so a source shorter than eight bytes simply has none.
        let fastLimit = srcN >= 8 ? srcN - 7 : 0

        var count = dest.count
        var buf   = dest.buffer
        var cap   = dest.capacity

        // Two literals, one whole match, and one vector store of overshoot.
        const FastSlack = 384'u64

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

            // Fast loop: runs while one whole symbol group fits both cursors' slack.
            //
            // The body is deliberately free of calls and of 'fail': the block's hottest
            // values — the bit buffer, its fill level, and both cursors — must live in
            // registers, and any call on a path inside the loop makes the allocator
            // spill them around the whole loop. Rare cases set 'stop' and break; the
            // code after the loop turns that into a return, a failure, or one careful
            // iteration below.
            if cur < fastLimit and cap - count > FastSlack
            {
                let obuf    = buf!
                var fastEnd = cap - FastSlack
                let left    = .outputLimit - (count - .outputStart)
                if left < fastEnd - count do
                    fastEnd = count + left

                // 0 = bounds exhausted, 1 = end of block, 2 = bad huffman code,
                // 3 = bad distance, 4 = redo this symbol in the careful loop.
                var stop = 0

                while count < fastEnd and cur < fastLimit
                {
                    cb  |= (src! + cur)[as u64] << #wrap nb
                    cur += cast(u64) ((63 - nb) >> 3)
                    nb  |= 56

                    var entry = repeatHt.fastEx[cb & FastMask]

                    // Literal burst: a compressed photograph is mostly literals, so
                    // take up to four straight ones before paying the loop bounds
                    // again. Four twelve-bit codes fit the fifty-six refilled bits.
                    if entry & EntryLiteral
                    {
                        var n = entry & 31
                        cb  >>= n
                        nb  -= n
                        obuf[count] = cast(u8) ((entry >> 16) & 0xFF)
                        count       += 1

                        entry = repeatHt.fastEx[cb & FastMask]
                        if entry & EntryLiteral
                        {
                            n   = entry & 31
                            cb  >>= n
                            nb  -= n
                            obuf[count] = cast(u8) ((entry >> 16) & 0xFF)
                            count       += 1

                            entry = repeatHt.fastEx[cb & FastMask]
                            if entry & EntryLiteral
                            {
                                n   = entry & 31
                                cb  >>= n
                                nb  -= n
                                obuf[count] = cast(u8) ((entry >> 16) & 0xFF)
                                count       += 1

                                entry = repeatHt.fastEx[cb & FastMask]
                                if entry & EntryLiteral
                                {
                                    n   = entry & 31
                                    cb  >>= n
                                    nb  -= n
                                    obuf[count] = cast(u8) ((entry >> 16) & 0xFF)
                                    count       += 1
                                    continue
                                }
                            }
                        }
                    }

                    var length: u64
                    if entry & EntryEob
                    {
                        let n = entry & 31
                        cb   >>= n
                        nb   -= n
                        stop = 1
                        break
                    }
                    elif entry == 0
                    {
                        // Rare: a code longer than 'FastBits'. Nothing of this symbol
                        // is consumed yet, so the careful loop can decode it whole.
                        stop = 4
                        break
                    }
                    else
                    {
                        let lbits  = entry & 31
                        let lextra = (entry >> 8) & 31
                        length = cast(u64) (entry >> 16) + ((cb >> lbits) & ((1'u64 << lextra) - 1))
                        let tot = lbits + lextra
                        cb  >>= tot
                        nb  -= tot
                    }

                    // The group may have consumed up to fifty-three bits; a far
                    // distance needs up to twenty-eight more, so top the buffer back
                    // up before reading it. Near the source's end this falls back to
                    // whole bytes: the OR is sound because every bit at or above 'nb'
                    // is either zero or already the correct next source bit.
                    if cur < fastLimit
                    {
                        cb  |= (src! + cur)[as u64] << #wrap nb
                        cur += cast(u64) ((63 - nb) >> 3)
                        nb  |= 56
                    }
                    else
                    {
                        let srcp = src!
                        while nb <= 56 and cur < srcN
                        {
                            cb  |= cast(u64) srcp[cur] << #wrap nb
                            cur += 1
                            nb  += 8
                        }
                    }

                    var distance: u64
                    let dentry = repeatZ.fastEx[cb & FastMask]
                    if dentry
                    {
                        let dbits  = dentry & 31
                        let dextra = (dentry >> 8) & 31
                        distance = cast(u64) (dentry >> 16) + ((cb >> dbits) & ((1'u64 << dextra) - 1))
                        let tot = dbits + dextra
                        cb  >>= tot
                        nb  -= tot
                    }
                    else
                    {
                        // Rare: a distance code longer than 'FastBits', walked inline
                        // so the loop stays call-free.
                        let k = reverse16(cast(u16) (cb & 0xFFFF), 16)
                        var s = HuffmanFastBits + 1
                        while k >= repeatZ.maxCode[s] do
                            s += 1
                        if s >= 16
                        {
                            stop = 2
                            break
                        }
                        let b1 = (k >> (16 - s)) - repeatZ.firstCode[s] + repeatZ.firstSymbol[s]
                        if b1 >= repeatZ.size.count or repeatZ.size[b1] != s
                        {
                            stop = 2
                            break
                        }
                        cb >>= cast(u32) s
                        nb -= #wrap cast(u32) s

                        let dvalue = repeatZ.value[b1]
                        distance = cast(u64) DistBase[dvalue]
                        let dextra = cast(u32) DistExtra[dvalue]
                        if dextra
                        {
                            distance += cb & ((1'u64 << dextra) - 1)
                            cb       >>= dextra
                            nb       -= dextra
                        }
                    }

                    if count < distance
                    {
                        stop = 3
                        break
                    }

                    if !length do
                        continue

                    let end  = count + length
                    var from = count - distance
                    if distance >= #sizeof(Math.Simd.U8x16)
                    {
                        // A distance of at least one vector makes each unaligned load
                        // independent of the store paired with it.
                        var dst = count
                        while dst < end
                        {
                            Math.Simd.store(obuf + dst, Math.Simd.load(obuf + from))
                            dst  += #sizeof(Math.Simd.U8x16)
                            from += #sizeof(Math.Simd.U8x16)
                        }
                    }
                    elif distance >= 8
                    {
                        // Non-overlapping in eight-byte steps.
                        var dst = count
                        while dst < end
                        {
                            (obuf + dst)[as u64] = (obuf + from)[as u64]
                            dst                  += 8
                            from                 += 8
                        }
                    }
                    else
                    {
                        // Replicate the short period across one vector once, then let
                        // every store advance by the largest whole number of periods.
                        let bytes = cast #bit(Math.Simd.U8x16) Math.Simd.splat((obuf + from)[as u64])
                        let pat   = Math.Simd.shuffle(bytes, PatternIndex[distance])
                        let adv   = PatternAdvance[distance]
                        var dst   = count
                        while dst < end
                        {
                            Math.Simd.store(obuf + dst, pat)
                            dst += adv
                        }
                    }

                    count = end
                }

                if stop == 1
                {
                    if nb != 64 do
                        cb &= (1'u64 << nb) - 1
                    .stream.codeBuffer = cb
                    .stream.numBits    = cast(u8) nb
                    .stream.curByte    = cur
                    dest.count         = count

                    let newSlice = Swag.makeSlice(dest.buffer + startBufCount, count - startBufCount)
                    .adler.update(newSlice)
                    return
                }

                if stop == 2 do
                    fail InvalidFormatError{"bad huffman code"}
                if stop == 3 do
                    fail InvalidFormatError{"bad distance"}

                // Bounds exhausted or a rare code: decode one symbol carefully below.
            }

            // Careful loop: near either cursor's end, or growing the destination.
            var value: u32
            var entry = repeatHt.fastEx[cb & FastMask]
            if entry & EntryLiteral
            {
                let n = entry & 31
                cb  >>= n
                nb  -= n
                value = (entry >> 16) & 0x1FF
            }
            elif entry & EntryEob
            {
                let n = entry & 31
                cb >>= n
                nb -= n
                value = 256
            }
            elif entry == 0
            {
                // Copies keep the loop-carried locals free of taken addresses, which
                // is what lets them live in registers through the fast loop.
                var tcb = cb
                var tnb = nb
                value   = decodeSlow(repeatHt, &tcb, &tnb)
                cb      = tcb
                nb      = tnb
            }
            else
            {
                value = 286     // Fast length entry: recovered below from the entry itself.
            }

            if value < 256
            {
                if count - .outputStart >= .outputLimit do
                    fail UnsupportedFormatError{"inflate output exceeds the configured limit"}
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

                let newSlice = Swag.makeSlice(dest.buffer + startBufCount, count - startBufCount)
                .adler.update(newSlice)
                return
            }

            var length: u64
            if entry & EntryLiteral or entry == 0
            {
                // The symbol came from the slow walk.
                let li = value - 257
                length = cast(u64) LengthBase[li]
                let lextra = cast(u32) LengthExtra[li]
                if lextra
                {
                    length += cb & ((1'u64 << lextra) - 1)
                    cb     >>= lextra
                    nb     -= lextra
                }
            }
            else
            {
                let lbits  = entry & 31
                let lextra = (entry >> 8) & 31
                length = cast(u64) (entry >> 16) + ((cb >> lbits) & ((1'u64 << lextra) - 1))
                let tot = lbits + lextra
                cb  >>= tot
                nb  -= tot
            }

            var distance: u64
            let dentry = repeatZ.fastEx[cb & FastMask]
            if dentry
            {
                let dbits  = dentry & 31
                let dextra = (dentry >> 8) & 31
                distance = cast(u64) (dentry >> 16) + ((cb >> dbits) & ((1'u64 << dextra) - 1))
                let tot = dbits + dextra
                cb  >>= tot
                nb  -= tot
            }
            else
            {
                var tcb = cb
                var tnb = nb
                let dvalue = decodeSlow(repeatZ, &tcb, &tnb)
                cb       = tcb
                nb       = tnb
                distance = cast(u64) DistBase[dvalue]
                let dextra = cast(u32) DistExtra[dvalue]
                if dextra
                {
                    distance += cb & ((1'u64 << dextra) - 1)
                    cb       >>= dextra
                    nb       -= dextra
                }
            }

            if count < distance do
                fail InvalidFormatError{"bad distance"}
            if !length do
                continue
            if count - .outputStart > .outputLimit or length > .outputLimit - (count - .outputStart) do
                fail UnsupportedFormatError{"inflate output exceeds the configured limit"}

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

    // Decompresses the associated stream, appending at most 'maxOutputSize' bytes to 'result'.
    public mtd decompress(result: *Array'u8, buf: const [..] u8, winSize: u32 = InflateMaxDistance, maxOutputSize: u64 = Swag.U64.Max) fail
    {
        .stream.reset(buf)
        .adler.reset()
        .windowSize  = Math.min(winSize, InflateMaxDistance)
        .outputLimit = maxOutputSize
        .outputStart = result.count

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
                if result.count - .outputStart > .outputLimit or uncompressedLen > .outputLimit - (result.count - .outputStart) do
                    fail UnsupportedFormatError{"inflate output exceeds the configured limit"}
                let newSlice = Swag.makeSlice(.stream.currentPointer(), uncompressedLen)
                .adler.update(newSlice)
                result.add(newSlice)
                .stream.advanceBytes(uncompressedLen)

            case 1:
                repeatHt.init(FixedLength, .Lengths)
                repeatZ.init(FixedDist, .Distances)
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

                codeLengthHt.init(codeLengthSizes, .Plain)
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
                repeatHt.init(lenCodes[0 to hlit - 1], .Lengths)
                repeatZ.init(lenCodes[hlit to ntot - 1], .Distances)
                .parseBlock(&repeatHt, &repeatZ, result)
            }

            if final == 1 do
                break
        }
    }
}
