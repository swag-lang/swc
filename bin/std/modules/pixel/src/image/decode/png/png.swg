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
        IHDR = Swag.byteSwap('I'_u32 << 24 | 'H'_u32 << 16 | 'D'_u32 << 8 | 'R'_u32)
        PLTE = Swag.byteSwap('P'_u32 << 24 | 'L'_u32 << 16 | 'T'_u32 << 8 | 'E'_u32)
        BKGD = Swag.byteSwap('b'_u32 << 24 | 'K'_u32 << 16 | 'G'_u32 << 8 | 'D'_u32)
        TRNS = Swag.byteSwap('t'_u32 << 24 | 'R'_u32 << 16 | 'N'_u32 << 8 | 'S'_u32)
        IDAT = Swag.byteSwap('I'_u32 << 24 | 'D'_u32 << 16 | 'A'_u32 << 8 | 'T'_u32)
        ITXt = Swag.byteSwap('i'_u32 << 24 | 'T'_u32 << 16 | 'X'_u32 << 8 | 't'_u32)
        TEXt = Swag.byteSwap('t'_u32 << 24 | 'E'_u32 << 16 | 'X'_u32 << 8 | 't'_u32)
        ZTXt = Swag.byteSwap('z'_u32 << 24 | 'T'_u32 << 16 | 'X'_u32 << 8 | 't'_u32)
        ICCP = Swag.byteSwap('i'_u32 << 24 | 'C'_u32 << 16 | 'C'_u32 << 8 | 'P'_u32)
        PHYs = Swag.byteSwap('p'_u32 << 24 | 'H'_u32 << 16 | 'Y'_u32 << 8 | 's'_u32)
        GAMA = Swag.byteSwap('g'_u32 << 24 | 'A'_u32 << 16 | 'M'_u32 << 8 | 'A'_u32)
        TIME = Swag.byteSwap('t'_u32 << 24 | 'I'_u32 << 16 | 'M'_u32 << 8 | 'E'_u32)
        SPLT = Swag.byteSwap('s'_u32 << 24 | 'P'_u32 << 16 | 'L'_u32 << 8 | 'T'_u32)
        SRGB = Swag.byteSwap('s'_u32 << 24 | 'R'_u32 << 16 | 'G'_u32 << 8 | 'B'_u32)
        HIST = Swag.byteSwap('h'_u32 << 24 | 'I'_u32 << 16 | 'S'_u32 << 8 | 'T'_u32)
        CHRM = Swag.byteSwap('c'_u32 << 24 | 'H'_u32 << 16 | 'R'_u32 << 8 | 'M'_u32)
        SBIT = Swag.byteSwap('s'_u32 << 24 | 'B'_u32 << 16 | 'I'_u32 << 8 | 'T'_u32)
        EXIf = Swag.byteSwap('e'_u32 << 24 | 'X'_u32 << 16 | 'I'_u32 << 8 | 'f'_u32)
        IEND = Swag.byteSwap('I'_u32 << 24 | 'E'_u32 << 16 | 'N'_u32 << 8 | 'D'_u32)
        IDOT = Swag.byteSwap('i'_u32 << 24 | 'D'_u32 << 16 | 'O'_u32 << 8 | 'T'_u32)
        CbGI = Swag.byteSwap('C'_u32 << 24 | 'b'_u32 << 16 | 'H'_u32 << 8 | 'I'_u32)
    }

    const Adam7OrigX:    [?] s64 = [0, 4, 0, 2, 0, 1, 0]
    const Adam7OrigY:    [?] s64 = [0, 0, 4, 0, 2, 0, 1]
    const Adam7SpacingX: [?] s64 = [8, 8, 4, 4, 2, 2, 1]
    const Adam7SpacingY: [?] s64 = [8, 8, 8, 4, 4, 2, 2]

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

    // The validated nonempty IDAT/fdAT chunks for an indexed frame. Other
    // ancillary chunks may lie between the first and last payload.
    struct FramePayload
    {
        first: const [*] u8?
        last:  const [*] u8?
        size:  u64
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
        dcmpBuf:       Array!{u8}             // Decompressed scanlines before defiltering.
        dstPixels:     [*] u8?                // Destination pixel buffer.
        dstPixelsSize: u64                    // Size of the destination buffer, in bytes.
        chunkTRNS:     DecodeChunk            // Transparency chunk, when the stream carries one.
        palette:       [256] u32              // Palette entries of an indexed stream.
        paletteCount:  s32                    // Number of valid palette entries.
        seenTRSN:      bool                   // Whether a transparency chunk was seen.
        seenBKGD:      bool                   // Whether a background chunk was seen.
        seenPLTE:      bool                   // Whether a palette chunk was seen.
        input:         const [..] u8?
        animation:     ImageSetInfo
        defaultData:   FramePayload
        frameData:     Array!{FramePayload}
        metadata:      Array!{ImageMetadata}
    }
}

private impl FramePayload
{
    mtd add(data: const [..] u8, skip: u64 = 0)
    {
        if data.count <= skip
        {
            return
        }

        let chunk = data.buffer - 8
        if not .first
        {
            .first = chunk
        }

        .last = chunk
        .size += data.count - skip
    }

    mtd assemble(joined: *Array!{u8})->const [..] u8
    {
        let first = .first
        if not first
        {
            return joined.toSlice()
        }

        let last = unwrap .last
        if first == last
        {
            let type = Swag.byteSwap(Decoder.read32Be(first + 4))
            return Swag.makeSlice(first + (type == cast(u32, ChunkType.IDAT) ? 8 : 12), .size)
        }

        joined.grow(.size)
        var chunk = first
        while chunk <= last
        {
            let length = Decoder.read32Be(chunk)
            let type   = Swag.byteSwap(Decoder.read32Be(chunk + 4))
            switch type
            {
            case cast(u32, ChunkType.IDAT):
                joined.add(Swag.makeSlice(chunk + 8, length))
            case cast(u32, ChunkType.FDAT):
                joined.add(Swag.makeSlice(chunk + 12, length - 4))
            default:
                break
            }

            chunk += cast(u64, length) + 12
        }

        Swag.assert(joined.count == .size)
        return joined.toSlice()
    }
}

impl Decoder
{
    // APNG fields live in chunk payloads whose addresses are not necessarily aligned.
    func read32Be(data: const [*] u8)->u32 => (cast(u32, data[0]) << 24) |
                                              (cast(u32, data[1]) << 16) |
                                              (cast(u32, data[2]) << 8) |
                                              cast(u32, data[3])

    func safeDatas(chunk: DecodeChunk)->const [..] u8 => cast(const [..] u8, unwrap chunk.datas)

    mtd getExpectedDecompressedSize()->u64
    {
        if .header.interlaceMethod == .None
        {
            return (.getStrideIn(.header.width) + 1) * .header.height
        }

        var result: u64
        for pass in 7
        {
            let originX = cast(u64, Adam7OrigX[pass])
            let originY = cast(u64, Adam7OrigY[pass])
            if .header.width <= originX or .header.height <= originY
            {
                continue
            }

            let spacingX = cast(u64, Adam7SpacingX[pass])
            let spacingY = cast(u64, Adam7SpacingY[pass])
            let width    = (.header.width - originX + spacingX - 1) / spacingX
            let height   = (.header.height - originY + spacingY - 1) / spacingY
            result += (.getStrideIn(cast(u32, width)) + 1) * height
        }

        return result
    }

    mtd safeTRNSData()->const [..] u8 => cast(const [..] u8, unwrap .chunkTRNS.datas)

    mtd safeDstPixels()->[*] u8 => unwrap .dstPixels

    mtd readChunk(ch: ChunkHeader)->DecodeChunk fail
    {
        var result: #returntype

        result.header = ch

        // Revert the bit reader's lookahead to reach the encoded chunk payload.
        .stream.revert()

        if .stream.bytePosition() + ch.length > .stream.size()
        {
            fail InvalidFormatError{"invalid chunk"}
        }

        let payload = unwrap .stream.currentPointer()
        result.datas = Swag.makeSlice(payload, ch.length)
        .stream.advanceBytes(ch.length)

        // The four bytes immediately before the payload are its type in wire order.
        let crc = Hash.Crc32.compute(Swag.makeSlice(payload - 4, cast(u64, ch.length) + 4))

        var vcrc: u32
        .stream.read32Be(cast([*] u8, &vcrc))
        if .stream.isEof()
        {
            fail InvalidFormatError{"PNG data ends before the chunk checksum"}
        }

        if vcrc != crc
        {
            fail InvalidFormatError{"invalid checksum"}
        }

        return result
    }

    mtd readHeader(ch: ChunkHeader) fail
    {
        if ch.length != 13
        {
            fail InvalidFormatError{"PNG IHDR chunk size is not 13 bytes"}
        }

        let chunk = try .readChunk(ch)
        .header        = cast(const *Header, (Decoder.safeDatas(chunk)).buffer)[]
        .header.width  = Math.bigEndianToNative(.header.width)
        .header.height = Math.bigEndianToNative(.header.height)

        with me.header
        {
            if .width == 0 or .height == 0
            {
                fail InvalidFormatError{"invalid dimensions"}
            }

            if cast(u64, .width) * .height > 0x1FFFFFFF
            {
                fail UnsupportedFormatError{"PNG image needs more than 2 GiB of decoded pixel memory"}
            }

            if .compressionMethod != 0
            {
                fail InvalidFormatError{"invalid compression mtd"}
            }

            if .filterMethod != 0
            {
                fail InvalidFormatError{"invalid filter mtd"}
            }

            if .interlaceMethod != .None and .interlaceMethod != .Adam7
            {
                fail InvalidFormatError{"invalid interlace mtd"}
            }

            switch cast(u8, .colorType)
            {
            case 0:
                if .bitDepth != 1 and
                   .bitDepth != 2 and
                   .bitDepth != 4 and
                   .bitDepth != 8 and
                   .bitDepth != 16
                {
                    fail UnsupportedFormatError{"unsupported bit depth"}
                }

            case 2:
                if .bitDepth != 8 and .bitDepth != 16
                {
                    fail UnsupportedFormatError{"unsupported bit depth"}
                }

            case 3:
                if .bitDepth != 1 and .bitDepth != 2 and .bitDepth != 4 and .bitDepth != 8
                {
                    fail UnsupportedFormatError{"unsupported bit depth"}
                }

            case 4, 6:
                if .bitDepth != 8 and .bitDepth != 16
                {
                    fail UnsupportedFormatError{"unsupported bit depth"}
                }

            default:
                fail InvalidFormatError{"invalid color type"}
            }

            if me.header.colorType & .Paletted
            {
                me.inChannels = 1
            }
            else if me.header.colorType & .Color
            {
                me.inChannels = 3
            }
            else
            {
                me.inChannels = 1
            }

            if me.header.colorType & .Alpha
            {
                me.inChannels += 1
            }

            let inputBytesPerPixel = cast(u64, me.inChannels) * (.bitDepth == 16 ? 2 : 1)
            if cast(u64, .width) * .height * inputBytesPerPixel > 0x7FFFFFFF
            {
                fail UnsupportedFormatError{"PNG image needs more than 2 GiB of decoded pixel memory"}
            }
        }
    }

    mtd(INDEX_FRAMES: bool) doIt(buffer: const [..] u8, selected: s32 = -1)->Image fail
    {
        .stream.reset(buffer)

        var signature: u64
        .stream.readBytes(#sizeof(signature), cast([*] u8, &signature))
        if signature != 0x0A1A0A0D474E5089
        {
            fail InvalidFormatError{"not a png"}
        }

        var result:    #returntype
        var frameData: Array!{u8}
        var firstIdat: const [..] u8?
        var idatSize:  u64
        #static if INDEX_FRAMES
        {
            var idatSpan: FramePayload
        }

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
                .stream.read32Be(cast([*] u8, &ch.length))
                .stream.read32(cast([*] u8, &ch.type))
            }

            chIsHere = false
            if .stream.isEof()
            {
                fail InvalidFormatError{"invalid chunk"}
            }

            if firstChunk and ch.type != .IHDR
            {
                fail InvalidFormatError{"PNG data does not start with an IHDR chunk"}
            }

            switch ch.type
            {
            case .IHDR:
                if not firstChunk
                {
                    fail InvalidFormatError{"PNG data contains more than one IHDR chunk"}
                }

                try .readHeader(ch)
                .animation.canvasWidth  = cast(s32, .header.width)
                .animation.canvasHeight = cast(s32, .header.height)

            case .ACTL:
                if declaredFrames or seenIDAT or ch.length != 8
                {
                    fail InvalidFormatError{"PNG animation control chunk is invalid or misplaced"}
                }

                let chunk = try .readChunk(ch)
                let data  = Decoder.safeDatas(chunk).buffer
                declaredFrames = .read32Be(data)
                if not declaredFrames
                {
                    fail InvalidFormatError{"PNG animation declares no frames"}
                }

                try .decOptions.checkFrameCount(declaredFrames)
                .animation.loopCount = .read32Be(data + 4)

            case .FCTL:
                if not declaredFrames or ch.length != 26 or (currentFrame >= 0 and not frameHasData)
                {
                    fail InvalidFormatError{"PNG animation frame control is invalid or misplaced"}
                }

                let chunk = try .readChunk(ch)
                let data  = Decoder.safeDatas(chunk).buffer
                if .read32Be(data) != sequence
                {
                    fail InvalidFormatError{"PNG animation sequence number is invalid"}
                }

                sequence     += 1
                currentFrame += 1
                frameHasData = false
                if cast(u32, currentFrame) >= declaredFrames
                {
                    fail InvalidFormatError{"PNG animation has too many frames"}
                }

                let width       = .read32Be(data + 4)
                let height      = .read32Be(data + 8)
                let x           = .read32Be(data + 12)
                let y           = .read32Be(data + 16)
                let numerator   = (cast(u16, data[20]) << 8) | data[21]
                let denominator = (cast(u16, data[22]) << 8) | data[23]
                if not width or
                   not height or
                   width > .header.width or
                   height > .header.height or
                   x > .header.width - width or
                   y > .header.height - height or
                   data[24] > 2 or
                   data[25] > 1
                {
                    fail InvalidFormatError{"PNG animation frame rectangle or operation is invalid"}
                }

                if not seenIDAT and (x or y or width != .header.width or height != .header.height)
                {
                    fail InvalidFormatError{"PNG default animation frame does not fill the canvas"}
                }

                let durationSeconds = cast(f64, numerator) / (denominator ? denominator : 100)
                var disposal: ImageDisposal
                if data[24] == 2
                {
                    disposal = currentFrame == 0 ? .Background : .Previous
                }
                else
                {
                    disposal = data[24] == 1 ? .Background : .Keep
                }

                let blend = data[25] ? ImageBlend.Over : .Replace
                let frame: ImageFrameInfo = ImageFrameInfo{
                    kind: .Animation,
                    width: cast(s32, width),
                    height: cast(s32, height),
                    x: cast(s32, x),
                    y: cast(s32, y),
                    durationSeconds: durationSeconds,
                    disposal: disposal,
                    blend: blend}
                .animation.frames.add(frame)
                #static if INDEX_FRAMES
                {
                    .frameData.add({})
                }

            case .FDAT:
                if not seenIDAT or currentFrame < 0 or ch.length < 4
                {
                    fail InvalidFormatError{"PNG animation frame data is invalid or misplaced"}
                }

                let chunk = try .readChunk(ch)
                let data  = Decoder.safeDatas(chunk)
                if .read32Be(data.buffer) != sequence
                {
                    fail InvalidFormatError{"PNG animation sequence number is invalid"}
                }

                sequence     += 1
                frameHasData = true
                #static if INDEX_FRAMES
                {
                    .frameData[currentFrame].add(data, 4)
                }
                else
                {
                    if .decOptions.decodePixels and selected == currentFrame
                    {
                        frameData.add(data[4 to])
                    }
                }

            case .TRNS:
                if .seenTRSN
                {
                    fail InvalidFormatError{"PNG data contains more than one tRNS chunk"}
                }

                if seenIDAT
                {
                    fail InvalidFormatError{"PNG tRNS chunk appears after image data"}
                }

                if .header.colorType & .Paletted and not .seenPLTE
                {
                    fail InvalidFormatError{"PNG indexed-color tRNS chunk appears before PLTE"}
                }

                if .header.colorType & .Alpha
                {
                    fail InvalidFormatError{"PNG image with alpha contains a tRNS chunk"}
                }

                .seenTRSN    = true
                .outChannels += 1     // transparency mask, add an alpha channel
                .chunkTRNS   = try .readChunk(ch)

                let transparencySize = (.safeTRNSData()).count
                if cast(u8, .header.colorType) == 0 and transparencySize != 2
                {
                    fail InvalidFormatError{"PNG grayscale tRNS chunk size is not 2 bytes"}
                }

                if cast(u8, .header.colorType) == 2 and transparencySize != 6
                {
                    fail InvalidFormatError{"PNG true-color tRNS chunk size is not 6 bytes"}
                }

                if .header.colorType & .Paletted and (transparencySize == 0 or transparencySize > .paletteCount)
                {
                    fail InvalidFormatError{"PNG indexed-color tRNS chunk exceeds the palette"}
                }

                if .header.bitDepth < 16
                {
                    let maxSample = (1_u32 << cast(u32, .header.bitDepth)) - 1
                    let data      = (.safeTRNSData()).buffer
                    if cast(u8, .header.colorType) == 0 and cast(u32, .read16(data)) > maxSample
                    {
                        fail InvalidFormatError{"PNG grayscale tRNS key exceeds the bit depth"}
                    }

                    if cast(u8, .header.colorType) == 2
                    {
                        for component in 3
                        {
                            if cast(u32, .read16(data + cast(u64, component) * 2)) > maxSample
                            {
                                fail InvalidFormatError{"PNG true-color tRNS key exceeds the bit depth"}
                            }
                        }
                    }
                }

            case .BKGD:
                if .seenBKGD
                {
                    fail InvalidFormatError{"PNG data contains more than one bKGD chunk"}
                }

                if seenIDAT
                {
                    fail InvalidFormatError{"PNG bKGD chunk appears after image data"}
                }

                if .header.colorType & .Paletted and not .seenPLTE
                {
                    fail InvalidFormatError{"PNG indexed-color bKGD chunk appears before PLTE"}
                }

                let chunk = try .readChunk(ch)
                let data  = Decoder.safeDatas(chunk)
                switch cast(u8, .header.colorType)
                {
                case 0, 4:
                    if data.count != 2
                    {
                        fail InvalidFormatError{"PNG grayscale bKGD chunk size is not 2 bytes"}
                    }

                    if .header.bitDepth < 16
                    {
                        let maxSample = (1_u32 << cast(u32, .header.bitDepth)) - 1
                        if cast(u32, .read16(data.buffer)) > maxSample
                        {
                            fail InvalidFormatError{"PNG grayscale bKGD sample exceeds the bit depth"}
                        }
                    }

                case 2, 6:
                    if data.count != 6
                    {
                        fail InvalidFormatError{"PNG true-color bKGD chunk size is not 6 bytes"}
                    }

                    if .header.bitDepth < 16
                    {
                        let maxSample = (1_u32 << cast(u32, .header.bitDepth)) - 1
                        for component in 3
                        {
                            if cast(u32, .read16(data.buffer + cast(u64, component) * 2)) > maxSample
                            {
                                fail InvalidFormatError{"PNG true-color bKGD sample exceeds the bit depth"}
                            }
                        }
                    }

                case 3:
                    if data.count != 1
                    {
                        fail InvalidFormatError{"PNG indexed-color bKGD chunk size is not 1 byte"}
                    }

                    if data[0] >= .paletteCount
                    {
                        fail InvalidFormatError{"PNG bKGD palette index exceeds the palette"}
                    }
                }

                .seenBKGD = true

            case .IEND:
                if ch.length
                {
                    fail InvalidFormatError{"PNG IEND chunk is not empty"}
                }

                seenIEND = true
                discard try .readChunk(ch)

            case .IDAT:
                if seenIDAT
                {
                    fail InvalidFormatError{"invalid IDAT chunk"}
                }

                while ch.type == IDAT
                {
                    let chunk = try .readChunk(ch)
                    #static if INDEX_FRAMES
                    {
                        idatSpan.add(Decoder.safeDatas(chunk))
                    }

                    if .decOptions.decodePixels and
                       (selected < 0 or selected == currentFrame) and
                       ch.length
                    {
                        if not firstIdat
                        {
                            firstIdat = Decoder.safeDatas(chunk)
                        }

                        idatSize += ch.length
                    }

                    if currentFrame >= 0
                    {
                        frameHasData = true
                    }

                    .stream.read32Be(cast([*] u8, &ch.length))
                    .stream.read32(cast([*] u8, &ch.type))
                    if .stream.isEof()
                    {
                        fail InvalidFormatError{"invalid chunk"}
                    }
                }

                #static if INDEX_FRAMES
                {
                    .defaultData = idatSpan
                    if currentFrame >= 0
                    {
                        .frameData[currentFrame] = idatSpan
                    }
                }

                chIsHere, seenIDAT = true

            case .PLTE:
                if .seenPLTE
                {
                    fail InvalidFormatError{"PNG data contains more than one PLTE chunk"}
                }

                if seenIDAT
                {
                    fail InvalidFormatError{"PNG PLTE chunk appears after image data"}
                }

                if .seenTRSN
                {
                    fail InvalidFormatError{"PNG PLTE chunk appears after tRNS"}
                }

                if .seenBKGD
                {
                    fail InvalidFormatError{"PNG PLTE chunk appears after bKGD"}
                }

                if cast(u8, .header.colorType) == 0 or cast(u8, .header.colorType) == 4
                {
                    fail InvalidFormatError{"PNG grayscale image contains a PLTE chunk"}
                }

                let chunk = try .readChunk(ch)
                let len   = (Decoder.safeDatas(chunk)).count
                if len == 0 or len % 3 != 0 or len > 768
                {
                    fail InvalidFormatError{"PNG PLTE chunk has no complete palette entries"}
                }

                if .header.colorType & .Paletted and len / 3 > 1 << .header.bitDepth
                {
                    fail InvalidFormatError{"PNG palette has more entries than its bit depth can address"}
                }

                .seenPLTE = true
                for var i = 0; i < len; i += 3
                {
                    let col = (cast(u32, Decoder.safeDatas(chunk)[i]) << 16) |
                              (cast(u32, Decoder.safeDatas(chunk)[i + 1]) << 8) |
                              Decoder.safeDatas(chunk)[i + 2]
                    .palette[i / 3] = col
                }

                .paletteCount = cast(u32, (len / 3))

            case .TEXt:
                let chunk = try .readChunk(ch)
                if .decOptions.decodeMetadata
                {
                    let len = (Decoder.safeDatas(chunk)).count
                    if len > 1
                    {
                        var sep = 0_u64
                        while sep < len and Decoder.safeDatas(chunk)[sep] != 0
                        {
                            sep += 1
                        }

                        var md: ImageMetadata
                        md.tag = cast(string, Decoder.safeDatas(chunk)[until sep])
                        if sep + 1 < len
                        {
                            md.value = cast(string, Decoder.safeDatas(chunk)[sep + 1 to])
                        }

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
                    metadata.value     = cast(string, Decoder.safeDatas(chunk))
                    result.metadata.add(#move metadata)
                }

            default:
                let typeBytes = cast(const [*] u8, &ch.type)
                if typeBytes[0] & 0x20 == 0
                {
                    fail UnsupportedFormatError{"PNG decoder does not support an unknown critical chunk"}
                }

                discard try .readChunk(ch)
            }

            firstChunk = false
        }

        if not seenIDAT
        {
            fail InvalidFormatError{"missing IDAT chunk"}
        }

        if .header.colorType & .Paletted and not .seenPLTE
        {
            fail InvalidFormatError{"missing PLTE chunk"}
        }

        if declaredFrames and (.animation.frames.count != declaredFrames or not frameHasData)
        {
            fail InvalidFormatError{"PNG animation frame count or data is incomplete"}
        }

        if selected >= 0
        {
            if selected >= .animation.frames.count
            {
                fail InvalidFormatError{"PNG animation frame index is out of range"}
            }

            .header.width  = cast(u32, .animation.frames[selected].width)
            .header.height = cast(u32, .animation.frames[selected].height)
        }

        // Initialize image at the source precision whenever Pixel has a matching storage format. init() resets
        // the whole Image payload, so keep metadata parsed from pre-IDAT chunks.
        var metadata  = #move result.metadata
        let colorType = cast(u8, .header.colorType)
        let is16Bit   = .header.bitDepth == 16
        var outputFormat: PixelFormat
        switch colorType
        {
        case 0:
            if is16Bit
            {
                outputFormat = .seenTRSN ? .GrayAlpha16 : .Gray16
            }
            else
            {
                outputFormat = .seenTRSN ? .GrayAlpha8 : .Gray8
            }

        case 2:
            if is16Bit
            {
                outputFormat = .seenTRSN ? .RGBA16 : .RGB16
            }
            else
            {
                outputFormat = .seenTRSN ? .RGBA8 : .RGB8
            }

        case 3:
            outputFormat = .seenTRSN ? .RGBA8 : .RGB8

        case 4:
            outputFormat = is16Bit ? .GrayAlpha16 : .GrayAlpha8

        case 6:
            outputFormat = is16Bit ? .RGBA16 : .RGBA8
        }

        .outChannels = outputFormat.channels()
        let imageWidth  = cast(s32, .header.width)
        let imageHeight = cast(s32, .header.height)
        try .decOptions.checkImage(imageWidth, imageHeight, outputFormat)
        let decodedBytes = cast(u64, .header.width) * .header.height * cast(u64, outputFormat.bitsPerPixel() / 8)
        if decodedBytes > 0x7FFFFFFF
        {
            fail UnsupportedFormatError{"PNG image needs more than 2 GiB of decoded pixel memory"}
        }

        result.init(imageWidth, imageHeight, outputFormat)
        result.metadata = #move metadata
        for &frame in .animation.frames
        {
            frame.pixelFormat = outputFormat
        }

        // We are done if user does not want pixels
        if not .decOptions.decodePixels
        {
            return result
        }

        // Validate all chunks before assembling the stream. A single payload needs no copy.
        var joined:     Array!{u8}
        var compressed: const [..] u8 = frameData.toSlice()
        if let first = firstIdat
        {
            if first.count == idatSize and frameData.isEmpty()
            {
                compressed = first
            }
            else
            {
                joined.grow(idatSize + frameData.count)
                var payload   = first.buffer
                var length    = first.count
                var remaining = idatSize
                for
                {
                    if length
                    {
                        joined.add(Swag.makeSlice(payload, length))
                    }

                    remaining -= length
                    if not remaining
                    {
                        break
                    }

                    // IDAT chunks are consecutive and have already been checked for size and CRC.
                    payload += length + 12
                    length  = Decoder.read32Be(payload - 8)
                }

                joined.add(frameData.toSlice())
                compressed = joined.toSlice()
            }
        }

        try .renderPixels(&result, compressed)
        return result
    }

    mtd renderPixels(result: *Image, compressed: const [..] u8) fail
    {
        let is16Bit = .header.bitDepth == 16
        // Native-depth rows can be defiltered in the final pixel buffer. For 16-bit samples,
        // swap byte order once the filters no longer need the encoded byte order.
        let bytesPerSample = .header.bitDepth == 16 ? 2_u64 : 1_u64
        .dstPixelsSize = cast(u64, .header.width) * .header.height * .inChannels * bytesPerSample
        var ownsDestination = false
        defer if ownsDestination
        {
            Memory.free(.dstPixels, .dstPixelsSize)
            .dstPixels = null
        }

        let intoResult = .header.bitDepth >= 8 and .inChannels == .outChannels
        let oneBitPalette = .header.bitDepth == 1 and
                            .header.colorType & .Paletted and
                            .header.interlaceMethod == .None and
                            .paletteCount == 2 and
                            .dstPixelsSize >= 64 * 1024
        if intoResult or oneBitPalette
        {
            result.allocPixels()
        }
        else
        {
            .dstPixels      = Memory.alloc(.dstPixelsSize)
            ownsDestination = true
        }

        var dec: Compress.ZLib
        let hintSize = .getExpectedDecompressedSize()
        .dcmpBuf = try dec.decompress(compressed, hintSize)
        if .dcmpBuf.count != hintSize
        {
            fail InvalidFormatError{"invalid PNG decompressed scanline size"}
        }

        if oneBitPalette
        {
            if not .convertOneBitPalette(result)
            {
                fail InvalidFormatError{"invalid PNG row filter"}
            }

            return
        }

        // defilter content
        if not .defilter(intoResult ? cast([*] u8, result.pixels.storage()) : .safeDstPixels())
        {
            fail InvalidFormatError{"invalid PNG row filter"}
        }

        // A complete palette covers every index representable by the source samples.
        if .header.colorType & .Paletted and .paletteCount < (1 << .header.bitDepth)
        {
            let pixelCount = cast(u64, .header.width) * .header.height
            if hasInvalidPaletteIndex(.safeDstPixels(), pixelCount, cast(u8, .paletteCount))
            {
                fail InvalidFormatError{"PNG pixel index exceeds the palette"}
            }
        }

        if intoResult
        {
            if is16Bit
            {
                let pixels = result.pixels.storage()
                convert16Samples(pixels, pixels, .dstPixelsSize / 2)
            }

            return
        }

        result.allocPixels()
        .convert(result)
    }
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"PNG - Portable Network Graphics", ".png;.apng"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        .decOptions = options
        return try .doIt!{false}(buffer)
    }
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        var indexed: Decoder
        indexed.input      = buffer
        indexed.decOptions = options
        indexed.decOptions.decodePixels = false
        var probe = try indexed.doIt!{true}(buffer)
        indexed.metadata = #move probe.metadata
        if not indexed.animation.frames.count
        {
            indexed.animation.frames.add({width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat})
        }

        me[] = #move indexed
        return .animation
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .animation.frames.count
        {
            fail InvalidFormatError{"PNG image index is out of range"}
        }

        let frame = &.animation.frames[index]
        var decoder: Decoder
        decoder.decOptions = options
        if options.decodeMetadata and not .decOptions.decodeMetadata
        {
            return try decoder.doIt!{false}(unwrap .input, frame.kind == .Animation ? cast(s32, index) : -1)
        }

        // ImageReader owns the bytes that open() validated. Use a fresh output
        // decoder so the indexed header, palette, and frame spans stay intact.
        decoder.header        = .header
        decoder.header.width  = cast(u32, frame.width)
        decoder.header.height = cast(u32, frame.height)
        decoder.inChannels    = .inChannels
        decoder.outChannels   = .outChannels
        decoder.seenPLTE      = .seenPLTE
        decoder.seenTRSN      = .seenTRSN
        decoder.chunkTRNS     = .chunkTRNS
        decoder.palette       = .palette
        decoder.paletteCount  = .paletteCount

        try options.checkFrameCount(.animation.frames.count)
        try options.checkImage(frame.width, frame.height, frame.pixelFormat)
        var result: #returntype
        result.init(frame.width, frame.height, frame.pixelFormat)
        if options.decodeMetadata
        {
            result.metadata = .metadata
        }

        if options.decodePixels
        {
            var joined: Array!{u8}
            let span = frame.kind == .Animation ? &.frameData[index] : &.defaultData
            try decoder.renderPixels(&result, span.assemble(&joined))
        }

        return result
    }
}
