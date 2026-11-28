// @LICENCE: LGPL-2.1-or-later
// @ORIGIN: FFmpeg n7.1, libavcodec/rv34.c and rv40.c
// @MODIFIED: 2026-11-15, bounded reader with compact RV40 decoding-tree indices.
// @NOTICE: THIRDPARTY.md#ffmpeg-realvideo-decoder
#global namespace RealVideo
#global internal

using Core, Core.Errors

// A bounded MSB-first reader. A malformed code poisons the reader until its caller rejects it.
struct Bits
{
    data:     const [*] u8?
    length:   u64
    position: u64
    broken:   bool
}

private const PrefixBits  = 8_u32
private const PrefixCount = 1_u32 << PrefixBits
private const RootCount   = IntraCbpPattern.count + IntraCbp.count + IntraFirst.count + IntraSecond.count + IntraThird.count + IntraCoeff.count +
                            InterCbpPattern.count + InterCbp.count + InterFirst.count + InterSecond.count + InterThird.count + InterCoeff.count +
                            AicTop.count + AicOne.count + PType.count + BType.count + AicTwo.count

private struct PrefixLookup
{
    roots:   [CodeTree.count / 2] u16
    entries: [RootCount * PrefixCount] u32
}

private const CodePrefixes: PrefixLookup = #run buildCodePrefixes()

private func buildCodePrefixes()->PrefixLookup
{
    var result: #returntype
    let groups: [17] const [..] s32 = [IntraCbpPattern, IntraCbp, IntraFirst, IntraSecond, IntraThird, IntraCoeff,
                                       InterCbpPattern, InterCbp, InterFirst, InterSecond, InterThird, InterCoeff,
                                       AicTop, AicOne, PType, BType, AicTwo]
    var row = 0_u32
    for group in groups
    {
        for root in group
        {
            result.roots[root] = cast(u16, row)
            for prefix in PrefixCount
            {
                var node   = cast(u32, root)
                var length = 0_u32
                for bit in PrefixBits
                {
                    let branch = (prefix >> (PrefixBits - 1 - bit)) & 1
                    node   = CodeTree[node * 2 + branch]
                    length += 1
                    if not node or node >= 0xF000
                    {
                        break
                    }
                }

                result.entries[row * PrefixCount + prefix] = length << 16 | node
            }

            row += 1
        }
    }

    Swag.require(row == RootCount)
    return result
}

impl Bits
{
    func open(data: const [..] u8)->Bits => Bits{data.buffer, data.count}

    #[Swag.Inline]
    mtd read(count: u32)->u32
    {
        if .broken
        {
            return 0
        }

        if count > 32 or count > .length * 8 - .position
        {
            .broken = true
            return 0
        }

        if not count
        {
            return 0
        }

        let byteIndex = .position >> 3
        let skip      = cast(u32, .position & 7)
        let first     = unwrap .data + byteIndex
        .position += count
        if skip + count <= 8
        {
            return (cast(u32, first[0]) >> (8 - skip - count)) & ((1_u32 << count) - 1)
        }

        let needed = (skip + count + 7) >> 3
        var value: u64
        if .length - byteIndex >= 8
        {
            value = Math.bigEndianToNative(cast(const [*] u64, first)[0]) >> (64 - skip - count)
        }
        else
        {
            for index in needed
            {
                value = (value << 8) | first[index]
            }

            value >>= needed * 8 - skip - count
        }

        return cast(u32, value & ((1_u64 << count) - 1))
    }

    mtd code(root: s32)->s32
    {
        if .broken
        {
            return 0
        }

        var node      = root
        var remaining = 24_u32

        // Two bytes cover an eight-bit prefix regardless of its alignment.
        if .length - (.position >> 3) >= 2
        {
            let bytes    = unwrap .data + (.position >> 3)
            let word     = Math.bigEndianToNative(cast(const [*] u16, bytes)[0])
            let prefix   = (cast(u32, word) >> (8 - cast(u32, .position & 7))) & 255
            let entry    = CodePrefixes.entries[cast(u32, CodePrefixes.roots[root]) * PrefixCount + prefix]
            let consumed = entry >> 16
            .position += consumed
            node      = cast(s32, entry & 0xFFFF)
            if node >= 0xF000
            {
                return node ^ 0xFFFF
            }

            if not node
            {
                .broken = true
                return 0
            }

            remaining -= consumed
        }

        for remaining
        {
            let branch = cast(s32, .read(1))
            node = cast(s32, CodeTree[node * 2 + branch])
            if node >= 0xF000
            {
                return node ^ 0xFFFF
            }

            if not node or .broken
            {
                break
            }
        }

        .broken = true
        return 0
    }

    mtd unsignedCode()->s32
    {
        var value = 1_s32
        for 24
        {
            if .read(1)
            {
                return value - 1
            }

            value = (value << 1) | cast(s32, .read(1))
            if .broken
            {
                break
            }
        }

        .broken = true
        return 0
    }

    mtd signedCode()->s32
    {
        let value = .unsignedCode()
        return (value & 1) != 0 ? (value + 1) / 2 : -(value / 2)
    }

    mtd dimension(height: bool)->s32
    {
        const Widths:  [8] s32  = [160, 172, 240, 320, 352, 640, 704, 0]
        const Heights: [12] s32 = [120, 132, 144, 240, 288, 480, -8, -10, 180, 360, 576, 0]
        let index = .read(3)
        var value = height ? Heights[index] : Widths[index]
        if value < 0
        {
            value = Heights[cast(s32, .read(1)) - value]
        }

        if not value
        {
            for 64
            {
                let part = cast(s32, .read(8))
                value += part * 4
                if part != 255
                {
                    return value
                }
            }

            .broken = true
        }

        return value
    }
}

struct SliceHeader
{
    kind:      s32
    quant:     s32
    set:       s32
    timestamp: s32
    width:     s32
    height:    s32
    start:     s32
}

impl SliceHeader
{
    func read(bits: *Bits, width, height: s32)->SliceHeader fail
    {
        var result: #returntype
        if bits.read(1)
        {
            fail InvalidFormatError{"RealVideo slice has a nonzero reserved bit"}
        }

        result.kind = cast(s32, bits.read(2))
        if result.kind == 1
        {
            result.kind = 0
        }

        result.quant = cast(s32, bits.read(5))
        if bits.read(2)
        {
            fail InvalidFormatError{"RealVideo slice has nonzero reserved bits"}
        }

        result.set = cast(s32, bits.read(2))
        discard bits.read(1)
        result.timestamp = cast(s32, bits.read(13))
        result.width     = width
        result.height    = height
        if result.kind == 0 or not bits.read(1)
        {
            result.width  = bits.dimension(false)
            result.height = bits.dimension(true)
        }

        if result.width <= 0 or result.height <= 0 or result.width > 8192 or result.height > 8192
        {
            fail InvalidFormatError{"RealVideo picture dimensions exceed the supported range"}
        }

        let count = ((result.width + 15) >> 4) * ((result.height + 15) >> 4)
        const Limits = [47, 98, 395, 1583, 6335, 9215]
        const Widths: [6] u32 = [6, 7, 9, 11, 13, 14]
        var index = 0_u32
        while index < 5 and Limits[index] < count - 1
        {
            index += 1
        }

        result.start = cast(s32, bits.read(Widths[index]))
        if bits.broken or result.start >= count
        {
            fail InvalidFormatError{"RealVideo slice header is truncated or its start exceeds the picture"}
        }

        return result
    }
}
