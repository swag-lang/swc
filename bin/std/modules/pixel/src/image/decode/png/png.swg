//! Format: Portable Network Graphics (PNG) decoder component.
//! Supported: Standard grayscale, true-color, indexed, grayscale-alpha, and true-color-alpha images, including Adam7 and supported metadata.
//! Not supported: Unknown critical chunks and images requiring more than 2 GiB of decoded storage.
//! Role: This file owns PNG chunk parsing, validation, and top-level decoding.
//
// @LICENCE: Zlib
// @ORIGIN: Odin PNG decoder, https://github.com/odin-lang/Odin/blob/master/core/image/png/png.odin
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#odin

#global namespace Png

using Swag, Core, Core.Errors

private
{
    enum ChunkType: u32
    {
        ACTL = 0x4C546361
        FCTL = 0x4C546366
        FDAT = 0x54416466
        IHDR = Swag.byteSwap('I'u32 << 24 | 'H'u32 << 16 | 'D'u32 << 8 | 'R'u32)
        PLTE = Swag.byteSwap('P'u32 << 24 | 'L'u32 << 16 | 'T'u32 << 8 | 'E'u32)
        BKGD = Swag.byteSwap('b'u32 << 24 | 'K'u32 << 16 | 'G'u32 << 8 | 'D'u32)
        TRNS = Swag.byteSwap('t'u32 << 24 | 'R'u32 << 16 | 'N'u32 << 8 | 'S'u32)
        IDAT = Swag.byteSwap('I'u32 << 24 | 'D'u32 << 16 | 'A'u32 << 8 | 'T'u32)
        ITXt = Swag.byteSwap('i'u32 << 24 | 'T'u32 << 16 | 'X'u32 << 8 | 't'u32)
        TEXt = Swag.byteSwap('t'u32 << 24 | 'E'u32 << 16 | 'X'u32 << 8 | 't'u32)
        ZTXt = Swag.byteSwap('z'u32 << 24 | 'T'u32 << 16 | 'X'u32 << 8 | 't'u32)
        ICCP = Swag.byteSwap('i'u32 << 24 | 'C'u32 << 16 | 'C'u32 << 8 | 'P'u32)
        PHYs = Swag.byteSwap('p'u32 << 24 | 'H'u32 << 16 | 'Y'u32 << 8 | 's'u32)
        GAMA = Swag.byteSwap('g'u32 << 24 | 'A'u32 << 16 | 'M'u32 << 8 | 'A'u32)
        TIME = Swag.byteSwap('t'u32 << 24 | 'I'u32 << 16 | 'M'u32 << 8 | 'E'u32)
        SPLT = Swag.byteSwap('s'u32 << 24 | 'P'u32 << 16 | 'L'u32 << 8 | 'T'u32)
        SRGB = Swag.byteSwap('s'u32 << 24 | 'R'u32 << 16 | 'G'u32 << 8 | 'B'u32)
        HIST = Swag.byteSwap('h'u32 << 24 | 'I'u32 << 16 | 'S'u32 << 8 | 'T'u32)
        CHRM = Swag.byteSwap('c'u32 << 24 | 'H'u32 << 16 | 'R'u32 << 8 | 'M'u32)
        SBIT = Swag.byteSwap('s'u32 << 24 | 'B'u32 << 16 | 'I'u32 << 8 | 'T'u32)
        EXIf = Swag.byteSwap('e'u32 << 24 | 'X'u32 << 16 | 'I'u32 << 8 | 'f'u32)
        IEND = Swag.byteSwap('I'u32 << 24 | 'E'u32 << 16 | 'N'u32 << 8 | 'D'u32)
        IDOT = Swag.byteSwap('i'u32 << 24 | 'D'u32 << 16 | 'O'u32 << 8 | 'T'u32)
        CbGI = Swag.byteSwap('C'u32 << 24 | 'b'u32 << 16 | 'H'u32 << 8 | 'I'u32)
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
        interlaceMethod:   InterlaceMethod
    }

    struct DecodeChunk
    {
        header: ChunkHeader
        datas:  const [..] u8?
        crc:    u32
    }
}

// Decodes PNG images, including palettes, transparency, filters, and Adam7 passes.
//
// The decoder is opaque and reports malformed chunks or unsupported data through `fail`.
#[Opaque]
internal struct Decoder
{
    // Decoding state of one image: the chunk cursor, the palette and transparency chunks it
    // collected, and the scanline buffers it defilters into. Decode through the module entry
    // points; nothing here survives the call.

    private
    {
        decOptions:    DecodeOptions          // Options the caller asked for.
        stream:        Compress.BitStream     // Bit cursor over the compressed data.
        header:        Header                 // Image header of the stream.
        inChannels:    s32                    // Channels present in the source.
        outChannels:   s32                    // Channels written to the destination.
        dcmpBuf:       Array'u8               // Decompressed scanlines before defiltering.
        dstPixels:     [*] u8?                // Destination pixel buffer.
        dstPixelsSize: u64                    // Size of the destination buffer, in bytes.
        chunkTRNS:     DecodeChunk            // Transparency chunk, when the stream carries one.
        palette:       [256] u32              // Palette entries of an indexed stream.
        paletteCount:  s32                    // Number of valid palette entries.
        seenTRSN:      bool                   // Whether a transparency chunk was seen.
        seenBKGD:      bool                   // Whether a background chunk was seen.
        seenPLTE:      bool                   // Whether a palette chunk was seen.
        orderDefilter: bool                   // Whether scanlines defilter in interlaced order.
        input:         const [..] u8?
        animation:     ImageSetInfo
    }
}

impl Decoder
{
    func safeDatas(chunk: DecodeChunk)->const [..] u8
    {
        return cast(const [..] u8) chunk.datas!
    }

    mtd safeTRNSData()->const [..] u8
    {
        return cast(const [..] u8) .chunkTRNS.datas!
    }

    mtd safeDstPixels()->[*] u8
    {
        return .dstPixels!
    }

    mtd readChunk(ch: ChunkHeader)->DecodeChunk fail
    {
        var result: retval

        result.header = ch

        // Resync the byte cursor before ? any raw pointer access: the bit reader may have
        // buffered bytes ahead of the consumed position (its refill loads several bytes at
        // once), so rewind those back into 'curByte' so 'curPtr' is the true chunk start.
        .stream.revert()

        if .stream.bytePosition() + ch.length > .stream.size() do
            fail InvalidFormatError{"invalid chunk"}
        result.datas = Swag.makeSlice(.stream.currentPointer(), ch.length)
        .stream.advanceBytes(ch.length)

        var crc: Hash.Crc32
        crc.update(Swag.makeSlice(cast(const [*] u8) &ch.type, 4))
        crc.update(Decoder.safeDatas(result))

        var vcrc: u32
        .stream.peek32Be(cast([*] u8) &vcrc)
        if .stream.isEof() do
            fail InvalidFormatError{"PNG data ends before the chunk checksum"}
        if vcrc != crc.value() do
            fail InvalidFormatError{"invalid checksum"}

        return result
    }

    mtd readHeader(ch: ChunkHeader) fail
    {
        if ch.length != 13 do
            fail InvalidFormatError{"PNG IHDR chunk size is not 13 bytes"}

        let chunk = try .readChunk(ch)
        .header        = (Decoder.safeDatas(chunk)).buffer[as Header]
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

            if me.header.colorType & .Paletted do
                me.inChannels = 1
            elif me.header.colorType & .Color do
                me.inChannels = 3
            else do
                me.inChannels = 1

            if me.header.colorType & .Alpha
            {
                me.inChannels += 1
            }

            let inputBytesPerPixel = cast(u64) me.inChannels * (.bitDepth == 16 ? 2 : 1)
            if cast(u64) .width * .height * inputBytesPerPixel > 0x7FFFFFFF do
                fail UnsupportedFormatError{"PNG image needs more than 2 GiB of decoded pixel memory"}
        }
    }

    // Expand 1, 2, 4 bits to 8 bits

    mtd doIt(buffer: const [..] u8, selected: s32 = -1)->Image fail
    {
        .stream.reset(buffer)

        var signature: u64
        .stream.peekBytes(#sizeof(signature), cast([*] u8) &signature)
        if signature != 0x0A1A0A0D474E5089 do
            fail InvalidFormatError{"not a png"}

        var result:   retval
        var iDataBuf: Array'u8

        // Zero-initialized: on iterations where 'chIsHere' skips the peek, the header
        // was already loaded by the look-ahead; the flow analysis cannot prove it.
        var ch: ChunkHeader

        var firstChunk          = true
        var seenIEND            = false
        var seenIDAT            = false
        var chIsHere            = false
        var declaredFrames: u32
        var sequence:       u64
        var frameHasData        = false
        var currentFrame:   s32 = -1

        while not seenIEND
        {
            // Peek a chunk header only if it's not already done
            if not chIsHere
            {
                .stream.peek32Be(cast([*] u8) &ch.length)
                .stream.peek32(cast([*] u8) &ch.type)
            }

            chIsHere = false
            if .stream.isEof() do
                fail InvalidFormatError{"invalid chunk"}
            if firstChunk and ch.type != .IHDR do
                fail InvalidFormatError{"PNG data does not start with an IHDR chunk"}

            switch ch.type
            {
            case .IHDR:
                if not firstChunk do
                    fail InvalidFormatError{"PNG data contains more than one IHDR chunk"}
                try .readHeader(ch)
                .animation.canvasWidth  = cast(s32) .header.width
                .animation.canvasHeight = cast(s32) .header.height

            case .ACTL:
                if declaredFrames or seenIDAT or ch.length != 8 do
                    fail InvalidFormatError{"PNG animation control chunk is invalid or misplaced"}
                let chunk = try .readChunk(ch)
                let data  = Decoder.safeDatas(chunk).buffer
                declaredFrames = Math.bigEndianToNative(data[as u32])
                if not declaredFrames do
                    fail InvalidFormatError{"PNG animation declares no frames"}
                try .decOptions.checkFrameCount(declaredFrames)
                .animation.loopCount = Math.bigEndianToNative((data + 4)[as u32])

            case .FCTL:
                if not declaredFrames or ch.length != 26 or (currentFrame >= 0 and not frameHasData) do
                    fail InvalidFormatError{"PNG animation frame control is invalid or misplaced"}
                let chunk = try .readChunk(ch)
                let data  = Decoder.safeDatas(chunk).buffer
                if Math.bigEndianToNative(data[as u32]) != sequence do
                    fail InvalidFormatError{"PNG animation sequence number is invalid"}
                sequence     += 1
                currentFrame += 1
                frameHasData = false
                if cast(u32) currentFrame >= declaredFrames do
                    fail InvalidFormatError{"PNG animation has too many frames"}
                let width       = Math.bigEndianToNative((data + 4)[as u32])
                let height      = Math.bigEndianToNative((data + 8)[as u32])
                let x           = Math.bigEndianToNative((data + 12)[as u32])
                let y           = Math.bigEndianToNative((data + 16)[as u32])
                let numerator   = Math.bigEndianToNative((data + 20)[as u16])
                let denominator = Math.bigEndianToNative((data + 22)[as u16])
                if not width or not height or width > .header.width or height > .header.height or x > .header.width - width or y > .header.height - height or data[24] > 2 or data[25] > 1 do
                    fail InvalidFormatError{"PNG animation frame rectangle or operation is invalid"}
                if not seenIDAT and (x or y or width != .header.width or height != .header.height) do
                    fail InvalidFormatError{"PNG default animation frame does not fill the canvas"}
                let frame: ImageFrameInfo = {kind: .Animation, width: cast(s32) width, height: cast(s32) height, x: cast(s32) x, y: cast(s32) y, durationSeconds: cast(f64) numerator / (denominator ? denominator : 100), disposal: data[24] == 2 ? (currentFrame == 0 ? .Background : .Previous) : (data[24] == 1 ? .Background : .Keep), blend: data[25] ? .Over : .Replace}
                .animation.frames.add(frame)

            case .FDAT:
                if not seenIDAT or currentFrame < 0 or ch.length < 4 do
                    fail InvalidFormatError{"PNG animation frame data is invalid or misplaced"}
                let chunk = try .readChunk(ch)
                let data  = Decoder.safeDatas(chunk)
                if Math.bigEndianToNative(data.buffer[as u32]) != sequence do
                    fail InvalidFormatError{"PNG animation sequence number is invalid"}
                sequence     += 1
                frameHasData = true
                if selected == currentFrame do
                    iDataBuf.add(data[4 to])

            case .TRNS:
                if .seenTRSN do
                    fail InvalidFormatError{"PNG data contains more than one tRNS chunk"}
                if seenIDAT do
                    fail InvalidFormatError{"PNG tRNS chunk appears after image data"}
                if .header.colorType & .Paletted and not .seenPLTE do
                    fail InvalidFormatError{"PNG indexed-color tRNS chunk appears before PLTE"}
                if .header.colorType & .Alpha do
                    fail InvalidFormatError{"PNG image with alpha contains a tRNS chunk"}

                .seenTRSN    = true
                .outChannels += 1     // transparency mask, add an alpha channel
                .chunkTRNS   = try .readChunk(ch)

                let transparencySize = (.safeTRNSData()).count
                if cast(u8) .header.colorType == 0 and transparencySize != 2 do
                    fail InvalidFormatError{"PNG grayscale tRNS chunk size is not 2 bytes"}
                if cast(u8) .header.colorType == 2 and transparencySize != 6 do
                    fail InvalidFormatError{"PNG true-color tRNS chunk size is not 6 bytes"}
                if .header.colorType & .Paletted and (transparencySize == 0 or transparencySize > .paletteCount) do
                    fail InvalidFormatError{"PNG indexed-color tRNS chunk exceeds the palette"}

            case .BKGD:
                .seenBKGD = true
                discard try .readChunk(ch)

            case .IEND:
                if ch.length do
                    fail InvalidFormatError{"PNG IEND chunk is not empty"}
                seenIEND = true
                discard try .readChunk(ch)

            case .IDAT:
                if seenIDAT do
                    fail InvalidFormatError{"invalid IDAT chunk"}
                while ch.type == IDAT
                {
                    let chunk = try .readChunk(ch)
                    if selected < 0 or selected == currentFrame do
                        iDataBuf.add(Decoder.safeDatas(chunk))
                    if currentFrame >= 0 do
                        frameHasData = true
                    .stream.peek32Be(cast([*] u8) &ch.length)
                    .stream.peek32(cast([*] u8) &ch.type)
                    if .stream.isEof() do
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
                let chunk = try .readChunk(ch)
                let len   = (Decoder.safeDatas(chunk)).count
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
                let chunk = try .readChunk(ch)
                if .decOptions.decodeMetadata
                {
                    let len = (Decoder.safeDatas(chunk)).count
                    if len > 1
                    {
                        var sep = 0'u64
                        while sep < len and Decoder.safeDatas(chunk)[sep] != 0 do
                            sep += 1

                        var md: ImageMetadata
                        md.tag = cast(string) Decoder.safeDatas(chunk)[until sep]
                        if sep + 1 < len do
                            md.value = cast(string) Decoder.safeDatas(chunk)[sep + 1 to]
                        result.metadata.add(md)
                    }
                }

            case .EXIf:
                let chunk = try .readChunk(ch)
                if .decOptions.decodeMetadata
                {
                    var metadata: ImageMetadata
                    metadata.tag       = "Exif"
                    metadata.signature = 1
                    metadata.value     = cast(string) Decoder.safeDatas(chunk)
                    result.metadata.add(#move metadata)
                }

            default:
                let typeBytes = cast(const [*] u8) &ch.type
                if typeBytes[0] & 0x20 == 0 do
                    fail UnsupportedFormatError{"PNG decoder does not support an unknown critical chunk"}
                discard try .readChunk(ch)
            }

            firstChunk = false
        }

        if not seenIDAT do
            fail InvalidFormatError{"missing IDAT chunk"}
        if .header.colorType & .Paletted and not .seenPLTE do
            fail InvalidFormatError{"missing PLTE chunk"}
        if declaredFrames and (.animation.frames.count != declaredFrames or not frameHasData) do
            fail InvalidFormatError{"PNG animation frame count or data is incomplete"}
        if selected >= 0
        {
            if selected >= .animation.frames.count do
                fail InvalidFormatError{"PNG animation frame index is out of range"}
            .header.width  = cast(u32) .animation.frames[selected].width
            .header.height = cast(u32) .animation.frames[selected].height
        }

        // Initialize image at the source precision whenever Pixel has a matching storage format. init() resets
        // the whole Image payload, so keep metadata parsed from pre-IDAT chunks.
        var metadata  = #move result.metadata
        let colorType = cast(u8) .header.colorType
        var outputFormat: PixelFormat
        switch colorType
        {
        case 0: outputFormat = .header.bitDepth == 16 ? (.seenTRSN ? .GrayAlpha16 : .Gray16) : (.seenTRSN ? .GrayAlpha8 : .Gray8)
        case 2: outputFormat = .header.bitDepth == 16 ? (.seenTRSN ? .RGBA16 : .RGB16) : (.seenTRSN ? .RGBA8 : .RGB8)
        case 3: outputFormat = .seenTRSN ? .RGBA8 : .RGB8
        case 4: outputFormat = .header.bitDepth == 16 ? .GrayAlpha16 : .GrayAlpha8
        case 6: outputFormat = .header.bitDepth == 16 ? .RGBA16 : .RGBA8
        }

        .outChannels = outputFormat.channels()
        result.init(cast(s32) .header.width, cast(s32) .header.height, outputFormat)
        result.metadata = #move metadata
        try .decOptions.checkImage(result.width, result.height, outputFormat)
        for &frame in .animation.frames do
            frame.pixelFormat = outputFormat

        // We are done if user does not want pixels
        if not .decOptions.decodePixels do
            return result

        // Allocate destination: defilter directly into result pixels when channels match
        // to avoid an extra full-image allocation and memcpy
        let bytesPerSample = .header.bitDepth == 16 ? 2'u64 : 1'u64
        .dstPixelsSize = cast(u64) .header.width * .header.height * .inChannels * bytesPerSample
        var ownsDestination = false
        defer if ownsDestination
        {
            Memory.free(.dstPixels, .dstPixelsSize)
            .dstPixels = null
        }

        if .header.bitDepth == 8 and .inChannels == .outChannels
        {
            result.allocPixels()
            .dstPixels = cast([*] u8) result.pixels.storage()
        }
        else
        {
            .dstPixels      = Memory.alloc(.dstPixelsSize)
            ownsDestination = true
        }

        // deflate content; hint the expected decompressed size to avoid realloc churn
        var dec: Compress.ZLib
        let hintSize = (.getStrideIn(.header.width) + 1) * .header.height
        .dcmpBuf = try dec.decompress(iDataBuf.toSlice(), hintSize)

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

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"PNG - Portable Network Graphics", ".png;.apng"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        .decOptions = options
        return try .doIt(buffer)
    }
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .input      = buffer
        .decOptions = options
        .decOptions.decodePixels = false
        let probe = try .doIt(buffer)
        if not .animation.frames.count do
            .animation.frames.add({width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat})
        return .animation
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .animation.frames.count do
            fail InvalidFormatError{"PNG image index is out of range"}
        var decoder: Decoder
        decoder.decOptions = options
        return try decoder.doIt(.input!, .animation.frames[index].kind == .Animation ? cast(s32) index : -1)
    }
}
