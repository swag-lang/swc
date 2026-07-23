/*
    :LICENCE
    This code is based on the Odin library (https://github.com/odin-lang/Odin/blob/master/core/image/png/png.odin)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Png
using Swag, Core, Core.Errors

private
{
    enum ChunkType: u32
    {
        IHDR = @byteswap('I''u32 << 24 | 'H''u32 << 16 | 'D''u32 << 8 | 'R''u32)
        PLTE = @byteswap('P''u32 << 24 | 'L''u32 << 16 | 'T''u32 << 8 | 'E''u32)
        BKGD = @byteswap('b''u32 << 24 | 'K''u32 << 16 | 'G''u32 << 8 | 'D''u32)
        TRNS = @byteswap('t''u32 << 24 | 'R''u32 << 16 | 'N''u32 << 8 | 'S''u32)
        IDAT = @byteswap('I''u32 << 24 | 'D''u32 << 16 | 'A''u32 << 8 | 'T''u32)

        ITXt = @byteswap('i''u32 << 24 | 'T''u32 << 16 | 'X''u32 << 8 | 't''u32)
        TEXt = @byteswap('t''u32 << 24 | 'E''u32 << 16 | 'X''u32 << 8 | 't''u32)
        ZTXt = @byteswap('z''u32 << 24 | 'T''u32 << 16 | 'X''u32 << 8 | 't''u32)

        ICCP = @byteswap('i''u32 << 24 | 'C''u32 << 16 | 'C''u32 << 8 | 'P''u32)
        PHYs = @byteswap('p''u32 << 24 | 'H''u32 << 16 | 'Y''u32 << 8 | 's''u32)
        GAMA = @byteswap('g''u32 << 24 | 'A''u32 << 16 | 'M''u32 << 8 | 'A''u32)
        TIME = @byteswap('t''u32 << 24 | 'I''u32 << 16 | 'M''u32 << 8 | 'E''u32)

        SPLT = @byteswap('s''u32 << 24 | 'P''u32 << 16 | 'L''u32 << 8 | 'T''u32)
        SRGB = @byteswap('s''u32 << 24 | 'R''u32 << 16 | 'G''u32 << 8 | 'B''u32)
        HIST = @byteswap('h''u32 << 24 | 'I''u32 << 16 | 'S''u32 << 8 | 'T''u32)
        CHRM = @byteswap('c''u32 << 24 | 'H''u32 << 16 | 'R''u32 << 8 | 'M''u32)
        SBIT = @byteswap('s''u32 << 24 | 'B''u32 << 16 | 'I''u32 << 8 | 'T''u32)

        EXIf = @byteswap('e''u32 << 24 | 'X''u32 << 16 | 'I''u32 << 8 | 'f''u32)
        IEND = @byteswap('I''u32 << 24 | 'E''u32 << 16 | 'N''u32 << 8 | 'D''u32)
        IDOT = @byteswap('i''u32 << 24 | 'D''u32 << 16 | 'O''u32 << 8 | 'T''u32)
        CbGI = @byteswap('C''u32 << 24 | 'b''u32 << 16 | 'H''u32 << 8 | 'I''u32)
    }

    const Adam7OrigX:    [?] s64 = [0, 4, 0, 2, 0, 1, 0]
    const Adam7OrigY:    [?] s64 = [0, 0, 4, 0, 2, 0, 1]
    const Adam7SpacingX: [?] s64 = [8, 8, 4, 4, 2, 2, 1]
    const Adam7SpacingY: [?] s64 = [8, 8, 8, 4, 4, 2, 2]

    enum RowFilter: u8
    {
        None    = 0
        Sub     = 1
        Up      = 2
        Average = 3
        Paeth   = 4
    }

    struct ChunkHeader
    {
        length: u32
        type:   ChunkType
    }

    enum InterlaceMethod: u8
    {
        None  = 0
        Adam7 = 1
    }

    #[Swag.EnumFlags]
    enum DecodeColorType: u8
    {
        Grayscale = 0
        Paletted  = 1
        Color     = 2
        Alpha     = 4
    }

    struct Header
    {
        width:             u32
        height:            u32
        bitDepth:          u8
        colorType:         DecodeColorType
        compressionMethod: u8
        filterMethod:      u8
        interlaceMethod:   InterlaceMethod = undefined
    }

    struct DecodeChunk
    {
        header: ChunkHeader
        datas:  #null const [..] u8
        crc:    u32
    }
}

#[Opaque]
public struct Decoder
{
    decOptions:    DecodeOptions
    stream:        Compress.BitStream
    header:        Header
    inChannels:    s32
    outChannels:   s32
    dcmpBuf:       Array'u8
    dstPixels:     #null [*] u8
    dstPixelsSize: u64
    chunkTRNS:     DecodeChunk
    palette:           [256] u32
    paletteCount:  s32
    seenTRSN:      bool
    seenBKGD:      bool
    seenPLTE:      bool
    orderDefilter: bool
}

impl Decoder
{
    func safeDatas(chunk: DecodeChunk)->const [..] u8
    {
        return cast(const [..] u8) (notnull chunk.datas)
    }

    mtd safeTRNSData()->const [..] u8
    {
        return cast(const [..] u8) (notnull .chunkTRNS.datas)
    }

    mtd safeDstPixels()->[*] u8
    {
        return notnull .dstPixels
    }

    mtd readChunk(ch: ChunkHeader)->DecodeChunk throw
    {
        var result: retval

        result.header = ch

        // Resync the byte cursor before #null any raw pointer access: the bit reader may have
        // buffered bytes ahead of the consumed position (its refill loads several bytes at
        // once), so rewind those back into 'curByte' so 'curPtr' is the true chunk start.
        .stream.revert()

        if .stream.curPtr() + ch.length > .stream.startPtr() + .stream.size() do
            throw InvalidFormatError{"invalid chunk"}
        result.datas    = @mkslice(.stream.curPtr(), ch.length)
        .stream.curByte += ch.length

        var crc: Hash.Crc32
        crc.update(@mkslice(cast(const [*] u8) &ch.type, 4))
        crc.update(Decoder.safeDatas(result))

        var vcrc: u32
        .stream.peek32Be(cast([*] u8) &vcrc)
        if vcrc != crc.crc do
            throw InvalidFormatError{"invalid checksum"}

        return result
    }

    mtd readHeader(ch: ChunkHeader) throw
    {
        let chunk = .readChunk(ch)
        .header        = dref cast(const *Header) @dataof(Decoder.safeDatas(chunk))
        .header.width  = Math.bigEndianToNative(.header.width)
        .header.height = Math.bigEndianToNative(.header.height)

        with me.header
        {
            if .width == 0 or .height == 0 do
                throw InvalidFormatError{"invalid dimensions"}
            if .compressionMethod != 0 do
                throw InvalidFormatError{"invalid compression mtd"}
            if .filterMethod != 0 do
                throw InvalidFormatError{"invalid filter mtd"}
            if .interlaceMethod != .None and .interlaceMethod != .Adam7 do
                throw InvalidFormatError{"invalid interlace mtd"}

            if cast(u8) .colorType > 7 do
                throw InvalidFormatError{"invalid color type"}
            if .bitDepth > 8 do
                throw UnsupportedFormatError{"unsupported bit depth"}

            me.outChannels = 3
            if me.header.colorType & .Paletted do
                me.inChannels = 1
            elif me.header.colorType & .Color do
                me.inChannels = 3
            else do
                me.inChannels = 1

            if me.header.colorType & .Alpha
            {
                me.inChannels  += 1
                me.outChannels += 1
            }

            if .bitDepth != 1 and .bitDepth != 2 and .bitDepth != 4 and .bitDepth != 8 do
                throw UnsupportedFormatError{"invalid bit depth"}
        }
    }

    func filterPaeth(left, up, upLeft: u8)->u8
    {
        let aa = cast(s16) left
        let bb = cast(s16) up
        let cc = cast(s16) upLeft
        let p  = aa + bb - cc
        let pa = Math.abs(cast(s16) (p - aa))
        let pb = Math.abs(cast(s16) (p - bb))
        let pc = Math.abs(cast(s16) (p - cc))
        if pa <= pb and pa <= pc do
            return left
        if pb <= pc do
            return up
        return upLeft
    }

    // Expand 1, 2, 4 bits to 8 bits
    mtd expand8(width, height: u32, output: [*] u8)
    {
        let rowStrideIn  = .getStrideIn(width)
        let rowStrideOut = .inChannels * width

        var orgDest   = output
        let srcOffset = rowStrideOut - rowStrideIn

        // 1 bit => 8 bits
        if .header.bitDepth == 1
        {
            let mul = .paletteCount ? 1 : 255
            for height
            {
                var dest = orgDest
                orgDest += rowStrideOut
                var src = dest + srcOffset
                var k   = rowStrideOut
                while k >= 8
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 7) * mul)
                    dest[1] = cast #bit (u8) (((c >> 6) & 1) * mul)
                    dest[2] = cast #bit (u8) (((c >> 5) & 1) * mul)
                    dest[3] = cast #bit (u8) (((c >> 4) & 1) * mul)
                    dest[4] = cast #bit (u8) (((c >> 3) & 1) * mul)
                    dest[5] = cast #bit (u8) (((c >> 2) & 1) * mul)
                    dest[6] = cast #bit (u8) (((c >> 1) & 1) * mul)
                    dest[7] = cast #bit (u8) ((c & 1) * mul)
                    dest    += 8
                    src     += 1
                    k       -= 8
                }
                if k > 0
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 7) * mul)
                    if k > 1 do
                        dest[1] = cast #bit (u8) (((c >> 6) & 1) * mul)
                    if k > 2 do
                        dest[2] = cast #bit (u8) (((c >> 5) & 1) * mul)
                    if k > 3 do
                        dest[3] = cast #bit (u8) (((c >> 4) & 1) * mul)
                    if k > 4 do
                        dest[4] = cast #bit (u8) (((c >> 3) & 1) * mul)
                    if k > 5 do
                        dest[5] = cast #bit (u8) (((c >> 2) & 1) * mul)
                    if k > 6 do
                        dest[6] = cast #bit (u8) (((c >> 1) & 1) * mul)
                }
            }
        }

        // 2 bits => 8 bits
        elif .header.bitDepth == 2
        {
            let mul = .paletteCount ? 1 : 85
            for height
            {
                var dest = orgDest
                orgDest += rowStrideOut
                var src = dest + srcOffset
                var k   = rowStrideOut
                while k >= 2
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 6) * mul)
                    dest[1] = cast #bit (u8) (((c >> 4) & 3) * mul)
                    dest[2] = cast #bit (u8) (((c >> 2) & 3) * mul)
                    dest[3] = cast #bit (u8) ((c & 3) * mul)
                    dest    += 4
                    src     += 1
                    k       -= 4
                }
                if k > 0
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 6) * mul)
                    if k > 1 do
                        dest[1] = cast #bit (u8) (((c >> 4) & 3) * mul)
                    if k > 2 do
                        dest[2] = cast #bit (u8) (((c >> 2) & 3) * mul)
                }
            }
        }

        // 4 bits => 8 bits
        elif .header.bitDepth == 4
        {
            let mul = .paletteCount ? 1 : 17
            for height
            {
                var dest = orgDest
                orgDest += rowStrideOut
                var src = dest + srcOffset
                var k   = rowStrideOut
                while k >= 2
                {
                    let c = src[0]
                    dest[0] = cast #bit (u8) ((c >> 4) * mul)
                    dest[1] = cast #bit (u8) ((c & 15) * mul)
                    dest    += 2
                    src     += 1
                    k       -= 2
                }
                if k > 0
                {
                    dest[0] = cast #bit (u8) ((src[0] >> 4) * mul)
                }
            }
        }
    }

    mtd getStrideIn(width: u32)->u64
    {
        if .header.bitDepth < 8 do
            return cast(u64) ((.inChannels * width * .header.bitDepth) + 7) / 8
        return cast(u64) .inChannels * width
    }

    mtd defilter8(width, height: u32, input, output: [*] u8)
    {
        let rowStrideIn  = .getStrideIn(width)
        let rowStrideOut = cast(u64) .inChannels * width
        let destOffset   = rowStrideOut - rowStrideIn

        var src  = input
        var dest = output
        if !.orderDefilter do
            dest += rowStrideOut * (height - 1)

        // A temporary line "before" the first one, if filter needs one
        var tmpRow: Array'u8
        tmpRow.resize(rowStrideOut)
        let tmpRowBuffer = notnull tmpRow.buffer
        Memory.clear(tmpRowBuffer, rowStrideOut)
        var up = tmpRowBuffer

        // PNG filtering references the previous byte of the same pixel. Packed
        // samples (bit depths below 8) have an effective byte offset of 1, not
        // the number of channels; otherwise narrow Adam7 passes underflow here.
        let filterOffset = .header.bitDepth < 8 ? 1'u64 : cast(u64) .inChannels
        let nk           = rowStrideIn > filterOffset ? rowStrideIn - filterOffset : 0
        var row = 0'u32
        while row < height
        {
            let filter = cast(RowFilter) src[0]
            src += 1

            var destOff = dest + destOffset
            switch filter
            {
            case None:
                Memory.copy(destOff, src, rowStrideIn)

            case Sub:
                var i = 0'u64
                while i < filterOffset
                {
                    destOff[i] = src[i]
                    i          += 1
                }
                var k = 0'u64
                while k < nk
                {
                    let idx = filterOffset + k
                    if idx >= rowStrideIn do
                        break
                    destOff[idx] = cast #bit (u8) (src[idx] + #wrap destOff[k])
                    k            += 1
                }

            case Up:
                var k = 0'u64
                while k < rowStrideIn
                {
                    destOff[k] = cast #bit (u8) (src[k] + #wrap up[k])
                    k          += 1
                }

            case Average:
                var i = 0'u64
                while i < filterOffset
                {
                    let avg = up[i] >> 1
                    destOff[i] = cast #bit (u8) (src[i] + #wrap avg)
                    i          += 1
                }
                var k = 0'u64
                while k < nk
                {
                    let idx = filterOffset + k
                    if idx >= rowStrideIn do
                        break
                    let avg = cast(u8) ((cast(u16) up[idx] + cast(u16) destOff[k]) >> 1)
                    destOff[idx] = cast #bit (u8) (src[idx] + #wrap avg)
                    k            += 1
                }

            case Paeth:
                var i = 0'u64
                while i < filterOffset
                {
                    let paeth = cast(u32) filterPaeth(0, up[i], 0)
                    destOff[i] = cast #bit (u8) (src[i] + paeth)
                    i          += 1
                }
                var k = 0'u64
                while k < nk
                {
                    let idx   = filterOffset + k
                    if idx >= rowStrideIn do
                        break
                    let paeth = cast(u32) filterPaeth(destOff[k], up[idx], up[k])
                    destOff[idx] = cast #bit (u8) (src[idx] + #wrap paeth)
                    k            += 1
                }
            }

            src += rowStrideIn
            up  = destOff
            if .orderDefilter do
                dest += rowStrideOut
            else do
                dest -= rowStrideOut
            row      += 1
        }
    }

    mtd defilter(width, height: u32, input, output: [*] u8)
    {
        if .header.bitDepth < 8
        {
            .defilter8(width, height, input, output)
            .expand8(width, height, output)
            return
        }

        if .header.bitDepth == 8
        {
            .defilter8(width, height, input, output)
            return
        }
    }

    mtd adam7()
    {
        var tmpArr: Array'u8
        var input   = notnull .dcmpBuf.buffer
        for p in 7
        {
            let x = (.header.width - Adam7OrigX[p] + Adam7SpacingX[p] - 1) / Adam7SpacingX[p]
            let y = (.header.height - Adam7OrigY[p] + Adam7SpacingY[p] - 1) / Adam7SpacingY[p]
            if x <= 0 or y <= 0 do
                continue

            tmpArr.resize(cast(u64) (x * y * .inChannels))
            let tmpBuffer = notnull tmpArr.buffer
            Memory.clear(tmpBuffer, tmpArr.count)

            .defilter(cast(u32) x, cast(u32) y, input, tmpBuffer)

            var t = tmpBuffer
            for j in y
            {
                for i in x
                {
                    let out_y   = .header.height - ((j * Adam7SpacingY[p]) + Adam7OrigY[p]) - 1
                    let out_x   = (i * Adam7SpacingX[p]) + Adam7OrigX[p]
                    var out_off = out_y * .header.width * .inChannels
                    out_off += out_x * .inChannels
                    for z in .inChannels do
                        .dstPixels[out_off + z] = t[z]
                    t                           += .inChannels
                }
            }

            let stride = (.getStrideIn(cast(u32) x) + 1) * y
            input += stride
        }
    }

    mtd defilter()
    {
        if .header.interlaceMethod != .Adam7
        {
            .orderDefilter = false
            let input = notnull .dcmpBuf.buffer
            .defilter(.header.width, .header.height, input, .safeDstPixels())
        }
        else
        {
            .orderDefilter = true
            .adam7()
        }
    }

    mtd doIt(buffer: const [..] u8)->Image throw
    {
        .stream.init(buffer)

        var signature: u64 = undefined
        .stream.peekBytes(#sizeof(signature), cast([*] u8) &signature)
        if signature != 0x0A1A0A0D474E5089 do
            throw InvalidFormatError{"not a png"}

        var result:   retval
        var iDataBuf: Array'u8
        // Zero-initialized: on iterations where 'chIsHere' skips the peek, the header
        // was already loaded by the look-ahead; the flow analysis cannot prove it.
        var ch: ChunkHeader

        var firstChunk = true
        var seenIEND   = false
        var seenIDAT   = false
        var chIsHere   = false

        while !seenIEND
        {
            // Peek a chunk header only if it's not already done
            if !chIsHere
            {
                .stream.peek32Be(cast([*] u8) &ch.length)
                .stream.peek32(cast([*] u8) &ch.type)
            }

            chIsHere = false
            if .stream.eof do
                throw InvalidFormatError{"invalid chunk"}

            switch ch.type
            {
            case IHDR:
                if !firstChunk do
                    throw InvalidFormatError{"invalid first chunk"}
                .readHeader(ch)

            case TRNS:
                .seenTRSN    = true
                .outChannels += 1     // transparency mask, add an alpha channel
                .chunkTRNS   = .readChunk(ch)

            case BKGD:
                .seenBKGD = true
                discard .readChunk(ch)

            case IEND:
                seenIEND = true
                discard .readChunk(ch)

            case IDAT:
                if seenIDAT do
                    throw InvalidFormatError{"invalid IDAT chunk"}
                while ch.type == IDAT
                {
                    let chunk = .readChunk(ch)
                    iDataBuf.add(Decoder.safeDatas(chunk))
                    .stream.peek32Be(cast([*] u8) &ch.length)
                    .stream.peek32(cast([*] u8) &ch.type)
                    if .stream.eof do
                        throw InvalidFormatError{"invalid chunk"}
                }

                chIsHere, seenIDAT = true

            case PLTE:
                if seenIDAT do
                    throw InvalidFormatError{"invalid PLTE chunk"}
                let chunk = .readChunk(ch)
                let len   = @countof(Decoder.safeDatas(chunk))
                if len % 3 != 0 or len > 768 do
                    throw InvalidFormatError{"invalid PLTE chunk"}
                .seenPLTE = true
                for var i = 0; i < len; i += 3
                {
                    let col = (cast(u32) Decoder.safeDatas(chunk)[i] << 16) | (cast(u32) Decoder.safeDatas(chunk)[i + 1] << 8) | Decoder.safeDatas(chunk)[i + 2]
                    .palette[i / 3] = col
                }

                .paletteCount = cast(u32) (len / 3)

            case TEXt:
                let chunk = .readChunk(ch)
                if .decOptions.decodeMetaDatas
                {
                    let len = @countof(Decoder.safeDatas(chunk))
                    if len > 1
                    {
                        var sep = 0'u64
                        while sep < len and Decoder.safeDatas(chunk)[sep] != 0 do
                            sep += 1

                        var md: ImageMetaData
                        md.tag = cast(string) Decoder.safeDatas(chunk)[until sep]
                        if sep + 1 < len do
                            md.value = cast(string) Decoder.safeDatas(chunk)[sep + 1 to]
                        result.metaDatas.add(md)
                    }
                }

            default:
                discard .readChunk(ch)
            }

            firstChunk = false
        }

        if !seenIDAT do
            throw InvalidFormatError{"missing IDAT chunk"}
        if .header.colorType & .Paletted and !.seenPLTE do
            throw InvalidFormatError{"missing PLTE chunk"}

        // Initialize image depending on number of wanted channels. init() resets
        // the whole Image payload, so keep metadata parsed from pre-IDAT chunks.
        var metaDatas = #move result.metaDatas
        if .outChannels == 4 do
            result.init(cast(s32) .header.width, cast(s32) .header.height, PixelFormat.RGBA8)
        else do
            result.init(cast(s32) .header.width, cast(s32) .header.height, PixelFormat.RGB8)
        result.metaDatas = #move metaDatas

        // We are done if user does not want pixels
        if !.decOptions.decodePixels do
            return result

        // Allocate destination: defilter directly into result pixels when channels match
        // to avoid an extra full-image allocation and memcpy
        .dstPixelsSize = .header.width * .header.height * .inChannels
        if .inChannels == .outChannels
        {
            result.allocPixels()
            .dstPixels = cast([*] u8) (notnull result.pixels.buffer)
        }
        else
        {
            .dstPixels = Memory.alloc(.dstPixelsSize)
        }

        // deflate content; hint the expected decompressed size to avoid realloc churn
        var dec: Compress.ZLib
        let hintSize = (.getStrideIn(.header.width) + 1) * .header.height
        .dcmpBuf = dec.decompress(iDataBuf.toSlice(), hintSize)

        // defilter content
        .defilter()

        // Channels match: result.pixels was already populated directly by defilter
        if .inChannels == .outChannels do
            return result

        result.allocPixels()
        .convert(&result)
        return result
    }

    mtd convert(result: *Image)
    {
        defer Memory.free(.safeDstPixels(), .dstPixelsSize)

        // Paletted, no transparency
        if .inChannels == 1 and .seenPLTE and !.seenTRSN
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                let pal  = src[0]
                let color = .palette[pal]
                dst[0] = cast() ((color >> 16) & 0xFF)
                dst[1] = cast() ((color >> 8) & 0xFF)
                dst[2] = cast() (color & 0xFF)
                src    += 1
                dst    += result.bpp8
            }
        }

        // Paletted, transparency
        elif .inChannels == 1 and .seenPLTE and .seenTRSN
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                let pal  = src[0]
                let color = .palette[pal]
                dst[0] = cast() ((color >> 16) & 0xFF)
                dst[1] = cast() ((color >> 8) & 0xFF)
                dst[2] = cast() (color & 0xFF)
                dst[3] = pal < @countof(.safeTRNSData()) ? .safeTRNSData()[pal] : 255
                src    += 1
                dst    += result.bpp8
            }
        }

        // Grayscale without alpha channel, no transparency
        elif .inChannels == 1 and !.seenTRSN
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                src    += 1
                dst    += result.bpp8
            }
        }

        // Grayscale without alpha channel, but transparency
        elif .inChannels == 1 and .seenTRSN
        {
            var key   = .safeTRNSData()[1]
            let scale = .header.bitDepth == 1 ? 255'u8 : .header.bitDepth == 2 ? 85'u8 : 17'u8
            key *= scale
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                dst[3] = src[0] == key ? 0 : 255
                src    += 1
                dst    += result.bpp8
            }
        }

        // Grayscale with alpha channel
        elif .inChannels == 2
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                dst[3] = src[1]
                src    += 2
                dst    += result.bpp8
            }
        }

        // Color without alpha but transparency
        elif .inChannels == 3 and .seenTRSN
        {
            let key  = cast(const [*] u8) @dataof(.safeTRNSData())
            let key0 = key[1]
            let key1 = key[3]
            let key2 = key[5]
            var src  = .safeDstPixels()
            var dst  = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[1]
                dst[2] = src[2]
                if src[0] == key0 and src[1] == key1 and src[2] == key2 do
                    dst[3] = 0
                else do
                    dst[3] = 255
                src        += 3
                dst        += result.bpp8
            }
        }
    }
}

public impl IImageDecoder for Decoder
{
    mtd impl canDecode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".png"
    }

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image throw
    {
        .decOptions = options
        return .doIt(buffer)
    }
}
