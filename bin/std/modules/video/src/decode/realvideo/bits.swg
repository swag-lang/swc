// @LICENCE: LGPL-2.1-or-later
// @ORIGIN: FFmpeg n7.1, libavcodec/rv34.c and rv40.c
// @MODIFIED: 2026-10-27, bounded Swag bit reader and RV40 slice header parsing.
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

impl Bits
{
    func open(data: const [..] u8)->Bits => Bits{data.buffer, data.count}

    mtd read(count: u32)->u32
    {
        if .broken do
            return 0
        if count > 32 or .position + count > .length * 8
        {
            .broken = true
            return 0
        }

        var result = 0'u32
        for count
        {
            result    = (result << 1) | ((cast(u32, .data![.position >> 3]) >> cast(u32, (7 - (.position & 7)))) & 1)
            .position += 1
        }

        return result
    }

    mtd code(root: s32)->s32
    {
        var node = root
        for 24
        {
            let branch = cast(s32, .read(1))
            node = CodeTree[node + branch]
            if node < 0 do
                return -node - 1
            if not node or .broken do
                break
        }

        .broken = true
        return 0
    }

    mtd unsignedCode()->s32
    {
        var value = 1's32
        for 24
        {
            if .read(1) do
                return value - 1
            value = (value << 1) | cast(s32, .read(1))
            if .broken do
                break
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
        if value < 0 do
            value = Heights[cast(s32, .read(1)) - value]
        if not value
        {
            for 64
            {
                let part = cast(s32, .read(8))
                value += part * 4
                if part != 255 do
                    return value
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
        if bits.read(1) do
            fail InvalidFormatError{"RealVideo slice has a nonzero reserved bit"}
        result.kind = cast(s32, bits.read(2))
        if result.kind == 1 do
            result.kind = 0
        result.quant = cast(s32, bits.read(5))
        if bits.read(2) do
            fail InvalidFormatError{"RealVideo slice has nonzero reserved bits"}
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

        if result.width <= 0 or result.height <= 0 or result.width > 8192 or result.height > 8192 do
            fail InvalidFormatError{"RealVideo picture dimensions exceed the supported range"}
        let count = ((result.width + 15) >> 4) * ((result.height + 15) >> 4)
        const Limits = [47, 98, 395, 1583, 6335, 9215]
        const Widths: [6] u32 = [6, 7, 9, 11, 13, 14]
        var index = 0'u32
        while index < 5 and Limits[index] < count - 1 do
            index += 1
        result.start = cast(s32, bits.read(Widths[index]))
        if bits.broken or result.start >= count do
            fail InvalidFormatError{"RealVideo slice header is truncated or its start exceeds the picture"}
        return result
    }
}
