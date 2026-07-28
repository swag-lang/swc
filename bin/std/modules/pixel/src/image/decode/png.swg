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
        IHDR = @byteswap('I'u32 << 24 | 'H'u32 << 16 | 'D'u32 << 8 | 'R'u32)
        PLTE = @byteswap('P'u32 << 24 | 'L'u32 << 16 | 'T'u32 << 8 | 'E'u32)
        BKGD = @byteswap('b'u32 << 24 | 'K'u32 << 16 | 'G'u32 << 8 | 'D'u32)
        TRNS = @byteswap('t'u32 << 24 | 'R'u32 << 16 | 'N'u32 << 8 | 'S'u32)
        IDAT = @byteswap('I'u32 << 24 | 'D'u32 << 16 | 'A'u32 << 8 | 'T'u32)

        ITXt = @byteswap('i'u32 << 24 | 'T'u32 << 16 | 'X'u32 << 8 | 't'u32)
        TEXt = @byteswap('t'u32 << 24 | 'E'u32 << 16 | 'X'u32 << 8 | 't'u32)
        ZTXt = @byteswap('z'u32 << 24 | 'T'u32 << 16 | 'X'u32 << 8 | 't'u32)

        ICCP = @byteswap('i'u32 << 24 | 'C'u32 << 16 | 'C'u32 << 8 | 'P'u32)
        PHYs = @byteswap('p'u32 << 24 | 'H'u32 << 16 | 'Y'u32 << 8 | 's'u32)
        GAMA = @byteswap('g'u32 << 24 | 'A'u32 << 16 | 'M'u32 << 8 | 'A'u32)
        TIME = @byteswap('t'u32 << 24 | 'I'u32 << 16 | 'M'u32 << 8 | 'E'u32)

        SPLT = @byteswap('s'u32 << 24 | 'P'u32 << 16 | 'L'u32 << 8 | 'T'u32)
        SRGB = @byteswap('s'u32 << 24 | 'R'u32 << 16 | 'G'u32 << 8 | 'B'u32)
        HIST = @byteswap('h'u32 << 24 | 'I'u32 << 16 | 'S'u32 << 8 | 'T'u32)
        CHRM = @byteswap('c'u32 << 24 | 'H'u32 << 16 | 'R'u32 << 8 | 'M'u32)
        SBIT = @byteswap('s'u32 << 24 | 'B'u32 << 16 | 'I'u32 << 8 | 'T'u32)

        EXIf = @byteswap('e'u32 << 24 | 'X'u32 << 16 | 'I'u32 << 8 | 'f'u32)
        IEND = @byteswap('I'u32 << 24 | 'E'u32 << 16 | 'N'u32 << 8 | 'D'u32)
        IDOT = @byteswap('i'u32 << 24 | 'D'u32 << 16 | 'O'u32 << 8 | 'T'u32)
        CbGI = @byteswap('C'u32 << 24 | 'b'u32 << 16 | 'H'u32 << 8 | 'I'u32)
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
    palette:       [256] u32
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

    mtd readChunk(ch: ChunkHeader)->DecodeChunk fail
    {
        var result: retval

        result.header = ch

        // Resync the byte cursor before #null any raw pointer access: the bit reader may have
        // buffered bytes ahead of the consumed position (its refill loads several bytes at
        // once), so rewind those back into 'curByte' so 'curPtr' is the true chunk start.
        .stream.revert()

        if .stream.curPtr() + ch.length > .stream.startPtr() + .stream.size() do
            fail InvalidFormatError{"invalid chunk"}
        result.datas    = @mkslice(.stream.curPtr(), ch.length)
        .stream.curByte += ch.length

        var crc: Hash.Crc32
        crc.update(@mkslice(cast(const [*] u8) &ch.type, 4))
        crc.update(Decoder.safeDatas(result))

        var vcrc: u32
        .stream.peek32Be(cast([*] u8) &vcrc)
        if .stream.eof do
            fail InvalidFormatError{"PNG data ends before the chunk checksum"}
        if vcrc != crc.crc do
            fail InvalidFormatError{"invalid checksum"}

        return result
    }

    mtd readHeader(ch: ChunkHeader) fail
    {
        if ch.length != 13 do
            fail InvalidFormatError{"PNG IHDR chunk size is not 13 bytes"}

        let chunk = .readChunk(ch)
        .header        = dref cast(const *Header) @dataof(Decoder.safeDatas(chunk))
        .header.width  = Math.bigEndianToNative(.header.width)
        .header.height = Math.bigEndianToNative(.header.height)

        with me.header
        {
            if .width == 0 or .height == 0 do
                fail InvalidFormatError{"invalid dimensions"}
            if cast(u64) .width * .height > 0x1FFFFFFF do
                fail UnsupportedFormatError{"PNG image needs more than 2 GiB of decoded pixel memory"}
            if .compressionMethod != 0 do
                fail InvalidFormatError{"invalid compression mtd"}
            if .filterMethod != 0 do
                fail InvalidFormatError{"invalid filter mtd"}
            if .interlaceMethod != .None and .interlaceMethod != .Adam7 do
                fail InvalidFormatError{"invalid interlace mtd"}

            switch cast(u8) .colorType
            {
            case 0:
                if .bitDepth != 1 and .bitDepth != 2 and .bitDepth != 4 and .bitDepth != 8 and .bitDepth != 16 do
                    fail UnsupportedFormatError{"unsupported bit depth"}

            case 2:
                if .bitDepth != 8 and .bitDepth != 16 do
                    fail UnsupportedFormatError{"unsupported bit depth"}

            case 3:
                if .bitDepth != 1 and .bitDepth != 2 and .bitDepth != 4 and .bitDepth != 8 do
                    fail UnsupportedFormatError{"unsupported bit depth"}

            case 4, 6:
                if .bitDepth != 8 and .bitDepth != 16 do
                    fail UnsupportedFormatError{"unsupported bit depth"}

            default:
                fail InvalidFormatError{"invalid color type"}
            }

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

            let inputBytesPerPixel = cast(u64) me.inChannels * (.bitDepth == 16 ? 2 : 1)
            if cast(u64) .width * .height * inputBytesPerPixel > 0x7FFFFFFF do
                fail UnsupportedFormatError{"PNG image needs more than 2 GiB of decoded pixel memory"}
        }
    }

    // Expand 1, 2, 4 bits to 8 bits

    mtd doIt(buffer: const [..] u8)->Image fail
    {
        .stream.init(buffer)

        var signature: u64 = undefined
        .stream.peekBytes(#sizeof(signature), cast([*] u8) &signature)
        if signature != 0x0A1A0A0D474E5089 do
            fail InvalidFormatError{"not a png"}

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
                fail InvalidFormatError{"invalid chunk"}
            if firstChunk and ch.type != .IHDR do
                fail InvalidFormatError{"PNG data does not start with an IHDR chunk"}

            switch ch.type
            {
            case .IHDR:
                if !firstChunk do
                    fail InvalidFormatError{"PNG data contains more than one IHDR chunk"}
                .readHeader(ch)

            case .TRNS:
                if .seenTRSN do
                    fail InvalidFormatError{"PNG data contains more than one tRNS chunk"}
                if seenIDAT do
                    fail InvalidFormatError{"PNG tRNS chunk appears after image data"}
                if .header.colorType & .Paletted and !.seenPLTE do
                    fail InvalidFormatError{"PNG indexed-color tRNS chunk appears before PLTE"}
                if .header.colorType & .Alpha do
                    fail InvalidFormatError{"PNG image with alpha contains a tRNS chunk"}

                .seenTRSN    = true
                .outChannels += 1     // transparency mask, add an alpha channel
                .chunkTRNS   = .readChunk(ch)

                let transparencySize = @countof(.safeTRNSData())
                if cast(u8) .header.colorType == 0 and transparencySize != 2 do
                    fail InvalidFormatError{"PNG grayscale tRNS chunk size is not 2 bytes"}
                if cast(u8) .header.colorType == 2 and transparencySize != 6 do
                    fail InvalidFormatError{"PNG true-color tRNS chunk size is not 6 bytes"}
                if .header.colorType & .Paletted and (transparencySize == 0 or transparencySize > .paletteCount) do
                    fail InvalidFormatError{"PNG indexed-color tRNS chunk exceeds the palette"}

            case .BKGD:
                .seenBKGD = true
                discard .readChunk(ch)

            case .IEND:
                if ch.length do
                    fail InvalidFormatError{"PNG IEND chunk is not empty"}
                seenIEND = true
                discard .readChunk(ch)

            case .IDAT:
                if seenIDAT do
                    fail InvalidFormatError{"invalid IDAT chunk"}
                while ch.type == IDAT
                {
                    let chunk = .readChunk(ch)
                    iDataBuf.add(Decoder.safeDatas(chunk))
                    .stream.peek32Be(cast([*] u8) &ch.length)
                    .stream.peek32(cast([*] u8) &ch.type)
                    if .stream.eof do
                        fail InvalidFormatError{"invalid chunk"}
                }

                chIsHere, seenIDAT = true

            case .PLTE:
                if .seenPLTE do
                    fail InvalidFormatError{"PNG data contains more than one PLTE chunk"}
                if seenIDAT do
                    fail InvalidFormatError{"PNG PLTE chunk appears after image data"}
                if .seenTRSN do
                    fail InvalidFormatError{"PNG PLTE chunk appears after tRNS"}
                if cast(u8) .header.colorType == 0 or cast(u8) .header.colorType == 4 do
                    fail InvalidFormatError{"PNG grayscale image contains a PLTE chunk"}
                let chunk = .readChunk(ch)
                let len   = @countof(Decoder.safeDatas(chunk))
                if len == 0 or len % 3 != 0 or len > 768 do
                    fail InvalidFormatError{"PNG PLTE chunk has no complete palette entries"}
                if .header.colorType & .Paletted and len / 3 > 1 << .header.bitDepth do
                    fail InvalidFormatError{"PNG palette has more entries than its bit depth can address"}
                .seenPLTE = true
                for var i = 0; i < len; i += 3
                {
                    let col = (cast(u32) Decoder.safeDatas(chunk)[i] << 16) | (cast(u32) Decoder.safeDatas(chunk)[i + 1] << 8) | Decoder.safeDatas(chunk)[i + 2]
                    .palette[i / 3] = col
                }

                .paletteCount = cast(u32) (len / 3)

            case .TEXt:
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
                let typeBytes = cast(const [*] u8) &ch.type
                if typeBytes[0] & 0x20 == 0 do
                    fail UnsupportedFormatError{"PNG decoder does not support an unknown critical chunk"}
                discard .readChunk(ch)
            }

            firstChunk = false
        }

        if !seenIDAT do
            fail InvalidFormatError{"missing IDAT chunk"}
        if .header.colorType & .Paletted and !.seenPLTE do
            fail InvalidFormatError{"missing PLTE chunk"}
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
        let bytesPerSample = .header.bitDepth == 16 ? 2'u64 : 1'u64
        .dstPixelsSize = cast(u64) .header.width * .header.height * .inChannels * bytesPerSample
        if .header.bitDepth == 8 and .inChannels == .outChannels
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
        if .header.bitDepth == 8 and .inChannels == .outChannels do
            return result

        result.allocPixels()
        .convert(&result)
        return result
    }
}

public impl IImageDecoder for Decoder
{
    mtd impl canDecode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".png"
    }

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        .decOptions = options
        return .doIt(buffer)
    }
}
