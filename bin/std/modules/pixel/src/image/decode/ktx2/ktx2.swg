//! Format: Khronos Texture 2 decoder.
//! Supported: All mip levels, array layers, cube faces, and depth slices of Vulkan RGB(A), grayscale, 16-bit and float formats;
//!            BC1 through BC5 blocks; and optional per-level ZLIB supercompression.
//! Not supported: BasisLZ, Zstandard, ETC/ASTC, or signed/depth pixel formats.
//! Role: This file validates KTX2 indices and decodes individual texture subresources.
//
#global namespace Ktx2

using Core, Core.Errors

const Identifier: [12] u8 = [0xAB, 'K', 'T', 'X', ' ', '2', '0', 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]
const HeaderSize = 80'u64

internal struct Decoder
{
    bytes:  const [..] u8?
    frames: Array'ImageFrameInfo
}

#[Swag.Inline]
func readU32(source: const [*] u8)->u32 => source[as u32]

#[Swag.Inline]
func readU64(source: const [*] u8)->u64 => source[as u64]

func vkPixelFormat(vk: u32, format: *PixelFormat, blocks: *TextureBlocks.Format)->bool
{
    switch vk
    {
    case 9, 15:    format[] = .Gray8
    case 16, 22:   format[] = .GrayAlpha8
    case 23, 29:   format[] = .RGB8
    case 30, 36:   format[] = .BGR8
    case 37, 43:   format[] = .RGBA8
    case 44, 50:   format[] = .BGRA8
    case 70:       format[] = .Gray16
    case 76:       format[] = .GrayF16
    case 77:       format[] = .GrayAlpha16
    case 83:       format[] = .GrayAlphaF16
    case 84:       format[] = .RGB16
    case 90:       format[] = .RGBF16
    case 91:       format[] = .RGBA16
    case 97:       format[] = .RGBAF16
    case 100:      format[] = .GrayF32
    case 103:      format[] = .GrayAlphaF32
    case 106:      format[] = .RGBF32
    case 109:      format[] = .RGBAF32
    case 131, 132, 133, 134: blocks[] = .BC1
    case 135, 136: blocks[] = .BC2
    case 137, 138: blocks[] = .BC3
    case 139:      blocks[] = .BC4
    case 141:      blocks[] = .BC5
    default:       return false
    }

    return true
}

func copyRows(image: *Image, source: const [..] u8, sourceTopDown: bool) fail
{
    let required = cast(u64) image.rowStride * cast(u64) image.height
    if source.count < required do
        fail InvalidFormatError{"KTX2 level data is truncated"}
    for y in image.height
    {
        let targetY = sourceTopDown ? image.height - y - 1 : y
        Memory.copy(image.pixels.storage() + cast(u64) targetY * image.rowStride,
                    source.buffer + cast(u64) y * image.rowStride,
                    cast(u64) image.rowStride)
    }
}

impl Decoder
{
    mtd decodeImage(buffer: const [..] u8, options: DecodeOptions, levelIndex: u32 = 0, imageIndex: u64 = 0)->Image fail
    {
        if buffer.count < HeaderSize + 24 do
            fail InvalidFormatError{"KTX2 header and level index are truncated"}
        for i in Identifier.count where buffer[i] != Identifier[i] do
            fail InvalidFormatError{"KTX2 identifier is invalid"}

        let vkFormat   = readU32(buffer.buffer + 12)
        let baseWidth  = readU32(buffer.buffer + 20)
        let baseHeight = readU32(buffer.buffer + 24)
        if levelIndex >= 32 do
            fail InvalidFormatError{"KTX2 mip level is out of range"}
        let width            = Math.max(baseWidth >> levelIndex, 1'u32)
        let height           = Math.max(baseHeight >> levelIndex, 1'u32)
        let depth            = readU32(buffer.buffer + 28)
        let layerCount       = readU32(buffer.buffer + 32)
        let faceCount        = readU32(buffer.buffer + 36)
        let levelCount       = readU32(buffer.buffer + 40)
        let storedLevelCount = Math.max(levelCount, 1'u32)
        let compression      = readU32(buffer.buffer + 44)
        let dfdOffset        = readU32(buffer.buffer + 48)
        let dfdLength        = readU32(buffer.buffer + 52)
        let kvdOffset        = readU32(buffer.buffer + 56)
        let kvdLength        = readU32(buffer.buffer + 60)
        if baseWidth == 0 or baseWidth > cast(u32) Swag.S32.Max or baseHeight > cast(u32) Swag.S32.Max do
            fail UnsupportedFormatError{"KTX2 dimensions exceed the image limits"}
        if (faceCount != 1 and faceCount != 6) or (depth and (faceCount != 1 or not baseHeight)) or (faceCount == 6 and baseWidth != baseHeight) do
            fail InvalidFormatError{"KTX2 texture dimensions and face count disagree"}
        if storedLevelCount > 32 or levelIndex >= storedLevelCount do
            fail InvalidFormatError{"KTX2 mip level is out of range"}
        if cast(u64) storedLevelCount > (buffer.count - HeaderSize) / 24 do
            fail InvalidFormatError{"KTX2 level index is truncated"}
        if dfdLength < 28 or cast(u64) dfdOffset + dfdLength > buffer.count or readU32(buffer.buffer + dfdOffset) != dfdLength do
            fail InvalidFormatError{"KTX2 data format descriptor is invalid"}
        if compression != 0 and compression != 3 do
            fail UnsupportedFormatError{"KTX2 supercompression must be absent or ZLIB"}

        var sourceTopDown = true
        if kvdLength
        {
            if cast(u64) kvdOffset + kvdLength > buffer.count do
                fail InvalidFormatError{"KTX2 key/value data exceeds the file"}
            var kvdPosition = cast(u64) kvdOffset
            let kvdEnd      = kvdPosition + kvdLength
            while kvdPosition < kvdEnd
            {
                if kvdEnd - kvdPosition < 4 do
                    fail InvalidFormatError{"KTX2 key/value length is truncated"}
                let entryLength = cast(u64) readU32(buffer.buffer + kvdPosition)
                kvdPosition += 4
                if entryLength > kvdEnd - kvdPosition do
                    fail InvalidFormatError{"KTX2 key/value entry is truncated"}
                var separator = 0'u64
                while separator < entryLength and buffer[kvdPosition + separator] do
                    separator += 1
                if separator == entryLength do
                    fail InvalidFormatError{"KTX2 key/value entry has no key terminator"}
                let key         = cast(string) Swag.makeSlice(buffer.buffer + kvdPosition, separator)
                let valueOffset = kvdPosition + separator + 1
                let valueLength = entryLength - separator - 1
                if key == "KTXorientation" and valueLength >= 2
                {
                    let vertical = buffer[valueOffset + 1]
                    if vertical != 'd' and vertical != 'u' do
                        fail InvalidFormatError{"KTX2 orientation has an invalid vertical direction"}
                    sourceTopDown = vertical == 'd'
                }

                kvdPosition = (kvdPosition + entryLength + 3) & ~3'u64
            }

            if kvdPosition != kvdEnd do
                fail InvalidFormatError{"KTX2 key/value padding exceeds its section"}
        }

        var format = PixelFormat.RGBA8
        var blocks: TextureBlocks.Format
        if not vkPixelFormat(vkFormat, &format, &blocks) do
            fail UnsupportedFormatError{"KTX2 Vulkan pixel format is not supported"}
        if blocks != .None do
            format = .RGBA8
        let flags     = buffer[cast(u64) dfdOffset + 15]
        let alphaMode = (flags & 1) != 0 and format.hasAlpha() ? AlphaMode.Premultiplied : AlphaMode.Straight

        var result: retval
        result.init(cast(s32) width, cast(s32) height, format, alphaMode)
        options.checkImage(result.width, result.height, format)

        let levelEntry  = HeaderSize + cast(u64) levelIndex * 24
        let levelOffset = readU64(buffer.buffer + levelEntry)
        let levelLength = readU64(buffer.buffer + levelEntry + 8)
        let rawLength   = readU64(buffer.buffer + levelEntry + 16)
        if levelOffset > buffer.count or levelLength > buffer.count - levelOffset do
            fail InvalidFormatError{"KTX2 base level points outside the file"}
        let imageCount = cast(u64) Math.max(layerCount, 1'u32) * faceCount * Math.max(depth >> levelIndex, 1'u32)
        if imageCount == 0 or rawLength % imageCount do
            fail InvalidFormatError{"KTX2 base level has an invalid layer size"}
        options.checkFrameCount(imageCount)
        if imageIndex >= imageCount do
            fail InvalidFormatError{"KTX2 image index is out of range"}
        let oneImageLength = blocks == .None ? result.byteCount : cast(u64) ((width + 3) / 4) * ((height + 3) / 4) * TextureBlocks.blockBytes(blocks)
        if rawLength / imageCount != oneImageLength do
            fail InvalidFormatError{"KTX2 level size disagrees with its image dimensions"}
        if options.maxDecodedBytes and rawLength > options.maxDecodedBytes do
            fail UnsupportedFormatError{"KTX2 level exceeds the decoded byte limit"}
        if not options.decodePixels do
            return result

        var inflated: Array'u8
        var level = buffer[levelOffset until levelOffset + levelLength]
        if compression == 3
        {
            var zlib: Compress.ZLib
            inflated = #move try zlib.decompress(level, rawLength)
            if inflated.count != rawLength do
                fail InvalidFormatError{"KTX2 ZLIB level has an invalid decoded size"}
            level = inflated.toSlice()
        }
        elif levelLength != rawLength do
            fail InvalidFormatError{"uncompressed KTX2 level sizes disagree"}

        let imageOffset = imageIndex * oneImageLength
        level = level[imageOffset until imageOffset + oneImageLength]
        result.allocPixels()
        if blocks != .None do
            try TextureBlocks.decode(&result, level, blocks, sourceTopDown)
        else do
            try copyRows(&result, level, sourceTopDown)
        return result
    }
}

impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"KTX2 - Khronos Texture", ".ktx2"}
    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail => .decodeImage(buffer, options)
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .bytes = buffer
        .frames.clear()
        var probeOptions = options
        probeOptions.decodePixels = false
        discard .decodeImage(buffer, probeOptions)
        let levels = Math.max(readU32(buffer.buffer + 40), 1'u32)
        let layers = Math.max(readU32(buffer.buffer + 32), 1'u32)
        let faces  = readU32(buffer.buffer + 36)
        let depth  = readU32(buffer.buffer + 28)
        for level in levels
        {
            let probe  = .decodeImage(buffer, probeOptions, level)
            let slices = Math.max(depth >> level, 1'u32)
            options.checkFrameCount(.frames.count + cast(u64) layers * faces * slices)
            for layer in layers
            {
                for face in faces
                {
                    for slice in slices
                    {
                        let frame: ImageFrameInfo = {kind: .Texture, width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat, level: level, layer: layer, face: face, depthSlice: slice}
                        .frames.add(frame)
                    }
                }
            }
        }

        var result: retval
        result.frames = .frames
        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .frames.count do
            fail InvalidFormatError{"KTX2 image index is out of range"}
        let frame  = &.frames[index]
        let buffer = .bytes!
        let faces  = readU32(buffer.buffer + 36)
        let slices = Math.max(readU32(buffer.buffer + 28) >> frame.level, 1'u32)
        return .decodeImage(buffer, options, frame.level, (cast(u64) frame.layer * faces + frame.face) * slices + frame.depthSlice)
    }
}
