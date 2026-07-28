#global namespace Webp

using Core, Core.Errors

const WEBP_FOURCC_RIFF = 0x46464952'u32
const WEBP_FOURCC_WEBP = 0x50424557'u32
const WEBP_FOURCC_VP8  = 0x20385056'u32
const WEBP_FOURCC_VP8L = 0x4C385056'u32
const WEBP_FOURCC_VP8X = 0x58385056'u32
const WEBP_FOURCC_ALPH = 0x48504C41'u32
const WEBP_FOURCC_ANIM = 0x4D494E41'u32
const WEBP_FOURCC_ANMF = 0x464D4E41'u32

const WEBP_FEATURE_ANIMATION = 0x02'u8
const WEBP_FEATURE_ALPHA     = 0x10'u8
const WEBP_RESERVED_FEATURES = 0xC1'u8

struct Chunk
{
    kind: u32
    data: #null const [*] u8
    size: u32
}

struct Container
{
    image:       Chunk
    alpha:       Chunk
    canvasWidth: s32
    canvasHeight: s32
    hasExtendedHeader: bool
    expectsAlpha:      bool
}

public struct Decoder {}

func readU24(data: const [*] u8)->u32
{
    return data[0] | (cast(u32) data[1] << 8) | (cast(u32) data[2] << 16)
}

func readU32(data: const [*] u8)->u32
{
    return data[0] | (cast(u32) data[1] << 8) | (cast(u32) data[2] << 16) | (cast(u32) data[3] << 24)
}

func parseContainer(buffer: const [..] u8)->Container fail
{
    if @countof(buffer) < 12 do
        fail InvalidFormatError{"WebP data ends before the RIFF header"}

    let source = @dataof(buffer)
    if readU32(source) != WEBP_FOURCC_RIFF or readU32(source + 8) != WEBP_FOURCC_WEBP do
        fail InvalidFormatError{"WebP data does not contain a RIFF WEBP header"}

    let riffSize = cast(u64) readU32(source + 4)
    if riffSize < 4 do
        fail InvalidFormatError{"WebP RIFF size does not include the WEBP form type"}
    if riffSize + 8 > @countof(buffer) do
        fail InvalidFormatError{"WebP data ends before the declared RIFF size"}

    var result: retval
    let riffEnd = source + riffSize + 8
    var cursor  = source + 12
    while cursor < riffEnd
    {
        if cursor + 8 > riffEnd do
            fail InvalidFormatError{"WebP data ends inside a chunk header"}

        let kind      = readU32(cursor)
        let chunkSize = readU32(cursor + 4)
        let chunkData = cursor + 8
        let paddedSize = cast(u64) chunkSize + (chunkSize & 1)
        if chunkData + paddedSize > riffEnd do
            fail InvalidFormatError{"WebP data ends before the declared chunk size"}

        switch kind
        {
        case WEBP_FOURCC_VP8X:
            if result.hasExtendedHeader do
                fail InvalidFormatError{"WebP data contains more than one VP8X chunk"}
            if cursor != source + 12 do
                fail InvalidFormatError{"WebP VP8X chunk is not the first chunk"}
            if chunkSize != 10 do
                fail InvalidFormatError{"WebP VP8X chunk size is not 10 bytes"}
            if chunkData[0] & WEBP_RESERVED_FEATURES or chunkData[1] or chunkData[2] or chunkData[3] do
                fail InvalidFormatError{"WebP VP8X chunk sets reserved bits"}
            if chunkData[0] & WEBP_FEATURE_ANIMATION do
                fail UnsupportedFormatError{"animated WebP images are not supported"}

            result.hasExtendedHeader = true
            result.expectsAlpha      = (chunkData[0] & WEBP_FEATURE_ALPHA) != 0
            result.canvasWidth       = cast(s32) readU24(chunkData + 4) + 1
            result.canvasHeight      = cast(s32) readU24(chunkData + 7) + 1
            if cast(u64) result.canvasWidth * result.canvasHeight > 0x1FFFFFFF do
                fail UnsupportedFormatError{"WebP canvas needs more than 2 GiB of decoded pixel memory"}

        case WEBP_FOURCC_ALPH:
            if !result.hasExtendedHeader or !result.expectsAlpha do
                fail InvalidFormatError{"WebP ALPH chunk is not declared by VP8X"}
            if result.alpha.data do
                fail InvalidFormatError{"WebP data contains more than one ALPH chunk"}
            if result.image.data do
                fail InvalidFormatError{"WebP ALPH chunk appears after the image data"}
            result.alpha = {kind: kind, data: chunkData, size: chunkSize}

        case WEBP_FOURCC_VP8, WEBP_FOURCC_VP8L:
            if result.image.data do
                fail InvalidFormatError{"WebP data contains more than one image chunk"}
            if kind == WEBP_FOURCC_VP8L and result.alpha.data do
                fail InvalidFormatError{"WebP lossless image also contains a separate ALPH chunk"}
            result.image = {kind: kind, data: chunkData, size: chunkSize}

        case WEBP_FOURCC_ANIM, WEBP_FOURCC_ANMF:
            fail UnsupportedFormatError{"animated WebP images are not supported"}
        }

        cursor = chunkData + paddedSize
    }

    if cursor != riffEnd do
        fail InvalidFormatError{"WebP chunks do not end at the declared RIFF size"}
    if !result.image.data do
        fail InvalidFormatError{"WebP data does not contain a VP8 or VP8L image chunk"}
    if result.expectsAlpha and result.image.kind == WEBP_FOURCC_VP8 and !result.alpha.data do
        fail InvalidFormatError{"WebP VP8X chunk declares alpha but no ALPH chunk is present"}
    return result
}

func flipRgbaRows(pixels: *Array'u8, width, height: s32)
{
    let rowBytes = cast(u64) width * 4
    let data     = cast([*] u8) notnull pixels.buffer
    for [y] in height / 2
    {
        var upper = cast(u64) y * rowBytes
        var lower = cast(u64) (height - y - 1) * rowBytes
        for rowBytes
        {
            swap(&data[upper], &data[lower])
            upper += 1
            lower += 1
        }
    }
}

func decodeLossless(container: Container, options: DecodeOptions)->Image fail
{
    let imageData = @mkslice(cast(const [*] u8) notnull container.image.data, container.image.size)
    var reader: LosslessBitReader = undefined
    var width, height: s32
    losslessDecodeHeader(&reader, imageData, &width, &height)

    if container.hasExtendedHeader and (width != container.canvasWidth or height != container.canvasHeight) do
        fail InvalidFormatError{"WebP VP8L dimensions differ from the VP8X canvas"}

    var result: retval
    result.init(width, height, .RGBA8)
    if !options.decodePixels do
        return result

    var pixels: Array'u8
    losslessDecode(imageData, &pixels, &width, &height)
    flipRgbaRows(&pixels, width, height)
    swap(&result.pixels, &pixels)
    return result
}

func vp8DecodeAlpha(container: Container, width, height: s32, alpha: *Array'u8) fail
{
    if !container.alpha.data do
        return
    if container.alpha.size == 0 do
        fail InvalidFormatError{"WebP ALPH chunk does not contain a control byte"}

    let source  = cast(const [*] u8) notnull container.alpha.data
    let control = source[0]
    if control & 0xC0 do
        fail InvalidFormatError{"WebP ALPH chunk sets reserved bits"}
    if ((control >> 4) & 3) > 1 do
        fail UnsupportedFormatError{"WebP ALPH chunk uses an unsupported preprocessing method"}

    let pixelCount = cast(u64) width * height
    switch control & 3
    {
    case 0:
        if container.alpha.size - 1 != pixelCount do
            fail InvalidFormatError{"WebP uncompressed ALPH byte count differs from the canvas dimensions"}
        alpha.resize(pixelCount)
        Memory.copy(cast([*] u8) notnull alpha.buffer, source + 1, pixelCount)

    case 1:
        let widthMinusOne  = cast(u32) width - 1
        let heightMinusOne = cast(u32) height - 1
        if widthMinusOne > 0x3FFF or heightMinusOne > 0x3FFF do
            fail InvalidFormatError{"WebP compressed ALPH dimensions exceed the VP8L header range"}

        var compressed: Array'u8
        compressed.resize(cast(u64) container.alpha.size + 4)
        compressed[0] = 0x2F
        compressed[1] = losslessWrap8(cast(s32) widthMinusOne)
        compressed[2] = losslessWrap8(cast(s32) ((widthMinusOne >> 8) | (heightMinusOne << 6)))
        compressed[3] = losslessWrap8(cast(s32) (heightMinusOne >> 2))
        compressed[4] = losslessWrap8(cast(s32) (heightMinusOne >> 10))
        Memory.copy(cast([*] u8) notnull compressed.buffer + 5, source + 1, container.alpha.size - 1)

        var rgba: Array'u8
        var decodedWidth, decodedHeight: s32
        losslessDecode(compressed.toSlice(), &rgba, &decodedWidth, &decodedHeight)
        if decodedWidth != width or decodedHeight != height do
            fail InvalidFormatError{"WebP compressed ALPH dimensions differ from the canvas"}
        alpha.resize(pixelCount)
        let alphaData = cast([*] u8) notnull alpha.buffer
        let rgbaData  = cast([*] u8) notnull rgba.buffer
        for [i] in pixelCount do
            alphaData[i] = rgbaData[4 * i + 1]

    default:
        fail UnsupportedFormatError{"WebP ALPH chunk uses an unsupported compression method"}
    }

    let data = cast([*] u8) notnull alpha.buffer
    let filter = (control >> 2) & 3
    if filter == 0 do
        return

    for [x] in width - 1 do
        data[x + 1] = losslessWrap8(data[x + 1] + data[x])

    if filter == 1
    {
        for [y] in height - 1
        {
            let row = cast(u64) (y + 1) * width
            data[row] = losslessWrap8(data[row] + data[row - width])
            for [x] in width - 1 do
                data[row + x + 1] = losslessWrap8(data[row + x + 1] + data[row + x])
        }
    }
    elif filter == 2
    {
        var i = cast(u64) width
        while i < pixelCount
        {
            data[i] = losslessWrap8(data[i] + data[i - width])
            i += 1
        }
    }
    else
    {
        for [y] in height - 1
        {
            let row = cast(u64) (y + 1) * width
            data[row] = losslessWrap8(data[row] + data[row - width])
            for [x] in width - 1
            {
                let offset = row + x + 1
                let prediction = vp8Clip(cast(s32) data[offset - 1] + data[offset - width] - data[offset - width - 1], 0, 255)
                data[offset] = losslessWrap8(data[offset] + prediction)
            }
        }
    }
}

func vp8ToRgba(decoder: *Vp8Decoder, alpha: *Array'u8, result: *Image)
{
    result.allocPixels()
    let yData   = cast([*] u8) notnull decoder.y.buffer
    let cbData  = cast([*] u8) notnull decoder.cb.buffer
    let crData  = cast([*] u8) notnull decoder.cr.buffer
    let outData = cast([*] u8) notnull result.pixels.buffer
    let aData   = alpha.buffer
    let width   = decoder.header.width
    let height  = decoder.header.height

    for [y] in height
    {
        let sourceRow      = y * decoder.yStride
        let chromaRow      = (y >> 1) * decoder.cStride
        var destination    = cast(u64) (height - y - 1) * width * 4
        let alphaRow       = cast(u64) y * width
        for [x] in width
        {
            let luma = cast(s32) yData[sourceRow + x]
            let cb   = cast(s32) cbData[chromaRow + (x >> 1)] - 128
            let cr   = cast(s32) crData[chromaRow + (x >> 1)] - 128
            let scaledLuma = luma * 0x10101
            outData[destination + 0] = vp8Clip8((scaledLuma + 91881 * cr) >> 16)
            outData[destination + 1] = vp8Clip8((scaledLuma - 22554 * cb - 46802 * cr) >> 16)
            outData[destination + 2] = vp8Clip8((scaledLuma + 116130 * cb) >> 16)
            outData[destination + 3] = aData ? aData[alphaRow + x] : 0xFF
            destination += 4
        }
    }
}

func decodeLossy(container: Container, options: DecodeOptions)->Image fail
{
    let imageData = @mkslice(cast(const [*] u8) notnull container.image.data, container.image.size)
    var decoder: Vp8Decoder = {source: @dataof(imageData)}
    vp8DecodeFrameHeader(&decoder, imageData)

    if container.hasExtendedHeader and
       (decoder.header.width != container.canvasWidth or decoder.header.height != container.canvasHeight)
    {
        fail InvalidFormatError{"WebP VP8 dimensions differ from the VP8X canvas"}
    }

    var result: retval
    result.init(decoder.header.width, decoder.header.height, .RGBA8)
    if !options.decodePixels do
        return result

    vp8ParseHeaders(&decoder)
    vp8AllocatePlanes(&decoder)
    for [mbY] in decoder.mbHeight
    {
        decoder.leftMb = {}
        for [mbX] in decoder.mbWidth
        {
            let skip = vp8Reconstruct(&decoder, mbX, mbY)
            var parameter = decoder.filterParams[decoder.segment][decoder.usePredY16 ? 0 : 1]
            parameter.inner = parameter.inner or !skip
            decoder.perMbFilterParams[decoder.mbWidth * mbY + mbX] = parameter
        }
    }

    if decoder.firstPart.unexpectedEnd do
        fail InvalidFormatError{"WebP data ends inside the VP8 control partition"}
    for [i] in decoder.otherPartCount do
        if decoder.otherParts[i].unexpectedEnd do
            fail InvalidFormatError{"WebP data ends inside a VP8 coefficient partition"}
    vp8ApplyFilter(&decoder)

    var alpha: Array'u8
    vp8DecodeAlpha(container, decoder.header.width, decoder.header.height, &alpha)
    vp8ToRgba(&decoder, &alpha, &result)
    return result
}

public impl IImageDecoder for Decoder
{
    mtd impl canDecode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".webp"
    }

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        let container = parseContainer(buffer)
        if container.image.kind == WEBP_FOURCC_VP8L do
            return decodeLossless(container, options)
        return decodeLossy(container, options)
    }
}
