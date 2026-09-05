//! Format: OpenEXR scanline decoder.
//! Supported: Single-part and multipart RGB, RGBA, or Y scanline images with half/float channels and
//!            no compression, ZIPS, or ZIP lossless compression.
//! Not supported: Tiled, deep, subsampled, UINT, PIZ/PXR24/B44/DWA/HTJ2K data,
//!                or layered channel names.
//! Role: This file reconstructs high-dynamic-range channels into half/full-float Pixel images.
//
#global namespace Exr

using Core, Core.Errors

const Magic = 20000630'u32

struct Channel
{
    name:      String
    pixelType: u32
}

internal struct Decoder { bytes: const [..] u8?; parts: Array'Part; multipart: bool }

#[Swag.Inline]
func readU32(source: const [*] u8)->u32 => source[as u32]

#[Swag.Inline]
func readU64(source: const [*] u8)->u64 => source[as u64]

func readText(buffer: const [..] u8, offset: *u64, maxLength: u64)->String fail
{
    let start = offset[]
    while offset[] < buffer.count and buffer[offset[]] and offset[] - start <= maxLength do
        offset[] += 1
    if offset[] >= buffer.count or offset[] - start > maxLength do
        fail InvalidFormatError{"OpenEXR header string is not terminated"}
    let result = String.from(cast(string) Swag.makeSlice(buffer.buffer + start, offset[] - start))
    offset[] += 1
    return result
}

func parseChannels(payload: const [..] u8)->Array'Channel fail
{
    var result: retval
    var offset = 0'u64
    while offset < payload.count and payload[offset]
    {
        let name = #move try readText(payload, &offset, 255)
        if offset + 16 > payload.count do
            fail InvalidFormatError{"OpenEXR channel entry is truncated"}
        let pixelType = readU32(payload.buffer + offset)
        let xSampling = readU32(payload.buffer + offset + 8)
        let ySampling = readU32(payload.buffer + offset + 12)
        if pixelType != 1 and pixelType != 2 do
            fail UnsupportedFormatError{"OpenEXR UINT channels are not supported"}
        if xSampling != 1 or ySampling != 1 do
            fail UnsupportedFormatError{"OpenEXR subsampled channels are not supported"}
        var channel: Channel
        channel.name      = #move name
        channel.pixelType = pixelType
        result.add(#move channel)
        offset += 16
    }

    if offset >= payload.count or payload[offset] != 0 do
        fail InvalidFormatError{"OpenEXR channel list is not terminated"}
    return result
}

func undoZipPredictor(data: [..] u8)
{
    if data.count < 2 do
        return
    var reordered: Array'u8
    reordered.resize(data.count)
    let firstHalf = (data.count + 1) / 2
    var even      = 0'u64
    var odd       = firstHalf
    for i in data.count
    {
        if i & 1
        {
            reordered[i] = data[odd]
            odd          += 1
        }
        else
        {
            reordered[i] = data[even]
            even         += 1
        }
    }

    for i in rangeTo(1'u64, data.count - 1) do
        reordered[i] = cast(u8) ((cast(u32) reordered[i - 1] + reordered[i] + 128) & 0xFF)
    Memory.copy(data.buffer, reordered.buffer, data.count)
}

func channelComponent(name: string)->s32
{
    switch name
    {
    case "R": return 0
    case "G": return 1
    case "B": return 2
    case "A": return 3
    case "Y": return 4
    }

    return -1
}

func writeChunk(image: *Image, channels: const [..] Channel, source: const [..] u8, firstY, rowCount, yMin: s32) fail
{
    var offset = 0'u64
    for row in rowCount
    {
        let fileY   = firstY + row
        let targetY = image.height - (fileY - yMin) - 1
        if targetY < 0 or targetY >= image.height do
            fail InvalidFormatError{"OpenEXR scanline lies outside the data window"}
        for &channel in channels
        {
            let bytes        = channel.pixelType == 1 ? 2'u64 : 4'u64
            let channelBytes = cast(u64) image.width * bytes
            if channelBytes > source.count - offset do
                fail InvalidFormatError{"OpenEXR channel pixels are truncated"}
            let component = channelComponent(channel.name.toString())
            if component >= 0
            {
                for x in image.width
                {
                    let input  = source.buffer + offset + cast(u64) x * bytes
                    let value  = channel.pixelType == 1 ? halfToFloat(input[as u16]) : input[as f32]
                    let target = image.pixels.buffer! + cast(u64) targetY * image.rowStride + cast(u64) x * image.bytesPerPixel
                    var pixel  = readPixelValue(target, image.pixelFormat)
                    switch component
                    {
                    case 0:
                        pixel.r = value

                    case 1:
                        pixel.g = value

                    case 2:
                        pixel.b = value

                    case 3:
                        pixel.a = value

                    case 4:
                        pixel.r = value
                        pixel.g = value
                        pixel.b = value
                    }

                    writePixelValue(target, image.pixelFormat, pixel)
                }
            }

            offset += channelBytes
        }
    }

    if offset != source.count do
        fail InvalidFormatError{"OpenEXR chunk has bytes after its channel data"}
}

struct Part
{
    channels:    Array'Channel
    compression: u8
    info:        ImageFrameInfo
    yMin:        s32
    rowBytes:    u64
    chunkCount:  u64
    tableOffset: u64
}

impl Part
{
    func parse(buffer: const [..] u8, offset: *u64, multipart: bool, options: DecodeOptions)->Part fail
    {
        var result: retval
        result.compression = 255
        var xMin, yMin, xMax, yMax: s32
        var hasDataWindow = false
        var declaredChunks:         u32
        var hasChunkCount = false
        var partType:               String
        while offset[] < buffer.count and buffer[offset[]]
        {
            let name = readText(buffer, offset, 255)
            let type = readText(buffer, offset, 255)
            if offset[] + 4 > buffer.count do
                fail InvalidFormatError{"OpenEXR attribute size is truncated"}
            let size = cast(u64) readU32(buffer.buffer + offset[])
            offset[] += 4
            if size > buffer.count - offset[] do
                fail InvalidFormatError{"OpenEXR attribute exceeds the file"}
            let payload = buffer[offset[] until offset[] + size]
            if name.toString() == "channels" and type.toString() == "chlist" do
                result.channels = parseChannels(payload)
            elif name.toString() == "compression" and type.toString() == "compression"
            {
                if size != 1 do
                    fail InvalidFormatError{"OpenEXR compression attribute has an invalid size"}
                result.compression = payload[0]
            }
            elif name.toString() == "dataWindow" and type.toString() == "box2i"
            {
                if size != 16 do
                    fail InvalidFormatError{"OpenEXR data window has an invalid size"}
                xMin          = cast #bit(s32) readU32(payload.buffer)
                yMin          = cast #bit(s32) readU32(payload.buffer + 4)
                xMax          = cast #bit(s32) readU32(payload.buffer + 8)
                yMax          = cast #bit(s32) readU32(payload.buffer + 12)
                hasDataWindow = true
            }
            elif name.toString() == "chunkCount" and type.toString() == "int"
            {
                if size != 4 do
                    fail InvalidFormatError{"OpenEXR chunk count has an invalid size"}
                declaredChunks = readU32(payload.buffer)
                hasChunkCount  = true
            }
            elif name.toString() == "name" and type.toString() == "string" do
                result.info.name = cast(string) payload
            elif name.toString() == "type" and type.toString() == "string" do
                partType = cast(string) payload
            offset[] += size
        }

        if offset[] >= buffer.count do
            fail InvalidFormatError{"OpenEXR header is not terminated"}
        offset[] += 1
        if !result.channels.count or !hasDataWindow or result.compression == 255 do
            fail InvalidFormatError{"OpenEXR required attributes are missing"}
        if multipart and (!hasChunkCount or !result.info.name.count or partType.toString() != "scanlineimage") do
            fail UnsupportedFormatError{"OpenEXR parts require a name, chunk count, and scanline image type"}
        if result.compression != 0 and result.compression != 2 and result.compression != 3 do
            fail UnsupportedFormatError{"OpenEXR compression is not NONE, ZIPS, or ZIP"}
        let width  = cast(s64) xMax - xMin + 1
        let height = cast(s64) yMax - yMin + 1
        if width <= 0 or height <= 0 or width > Swag.S32.Max or height > Swag.S32.Max do
            fail InvalidFormatError{"OpenEXR data window dimensions are invalid"}
        var hasR, hasG, hasB, hasY, hasAlpha, hasFloat: bool
        for channel in result.channels
        {
            switch channel.name.toString()
            {
            case "R": hasR = true
            case "G": hasG = true
            case "B": hasB = true
            case "Y": hasY = true
            case "A": hasAlpha = true
            default:  fail UnsupportedFormatError{"OpenEXR layered or auxiliary channels are not supported"}
            }

            hasFloat        = hasFloat or channel.pixelType == 2
            result.rowBytes += cast(u64) width * (channel.pixelType == 1 ? 2 : 4)
        }

        if !(hasY or (hasR and hasG and hasB)) do
            fail UnsupportedFormatError{"OpenEXR image has neither Y nor RGB color channels"}
        let grayscale           = hasY and !(hasR and hasG and hasB)
        let format: PixelFormat = hasFloat ? (grayscale ? (hasAlpha ? .GrayAlphaF32 : .GrayF32) : (hasAlpha ? .RGBAF32 : .RGBF32)) : (grayscale ? (hasAlpha ? .GrayAlphaF16 : .GrayF16) : (hasAlpha ? .RGBAF16 : .RGBF16))
        result.info.kind        = multipart ? .Page : .Still
        result.info.width       = cast(s32) width
        result.info.height      = cast(s32) height
        result.info.x           = xMin
        result.info.y           = yMin
        result.info.pixelFormat = format
        result.yMin             = yMin
        options.checkImage(result.info.width, result.info.height, format)
        let linesPerChunk = result.compression == 3 ? 16'u64 : 1'u64
        result.chunkCount = (cast(u64) height + linesPerChunk - 1) / linesPerChunk
        if hasChunkCount and declaredChunks != result.chunkCount do
            fail InvalidFormatError{"OpenEXR chunk count disagrees with the data window"}
        return result
    }

    mtd decode(buffer: const [..] u8, index: u32, multipart: bool, options: DecodeOptions)->Image fail
    {
        var result: retval
        result.init(.info.width, .info.height, .info.pixelFormat)
        if !options.decodePixels do
            return result
        result.allocPixels()
        result.fill(Argb.Black)
        let linesPerChunk = .compression == 3 ? 16'u64 : 1'u64
        var seenRows: Array'bool
        seenRows.resize(cast(u64) .info.height)
        for chunkIndex in .chunkCount
        {
            var chunkOffset = readU64(buffer.buffer + .tableOffset + chunkIndex * 8)
            let headerSize  = multipart ? 12'u64 : 8'u64
            if chunkOffset > buffer.count or headerSize > buffer.count - chunkOffset do
                fail InvalidFormatError{"OpenEXR chunk offset points outside the file"}
            if multipart
            {
                if readU32(buffer.buffer + chunkOffset) != index do
                    fail InvalidFormatError{"OpenEXR chunk belongs to another part"}
                chunkOffset += 4
            }

            let firstY     = cast #bit(s32) readU32(buffer.buffer + chunkOffset)
            let packedSize = cast(u64) readU32(buffer.buffer + chunkOffset + 4)
            if packedSize > buffer.count - chunkOffset - 8 do
                fail InvalidFormatError{"OpenEXR chunk is truncated"}
            let relativeY = cast(s64) firstY - .yMin
            if relativeY < 0 or relativeY >= .info.height or cast(u64) relativeY % linesPerChunk do
                fail InvalidFormatError{"OpenEXR chunk starts outside its scanline block"}
            let rows = Math.min(cast(s32) linesPerChunk, .info.height - cast(s32) relativeY)
            for row in rows
            {
                let y = cast(u64) relativeY + cast(u64) row
                if seenRows[y] do
                    fail InvalidFormatError{"OpenEXR scanline occurs more than once"}
                seenRows[y] = true
            }

            let expected = .rowBytes * cast(u64) rows
            if options.maxDecodedBytes and expected > options.maxDecodedBytes do
                fail UnsupportedFormatError{"OpenEXR chunk exceeds the decoded byte limit"}
            var unpacked: Array'u8
            var pixels = buffer[chunkOffset + 8 until chunkOffset + 8 + packedSize]
            if .compression and packedSize != expected
            {
                var zlib: Compress.ZLib
                unpacked = zlib.decompress(pixels, expected)
                if unpacked.count != expected do
                    fail InvalidFormatError{"OpenEXR ZIP chunk has an invalid decoded size"}
                undoZipPredictor(unpacked.toSlice())
                pixels = unpacked.toSlice()
            }

            if pixels.count != expected do
                fail InvalidFormatError{"OpenEXR scanline chunk has an invalid size"}
            writeChunk(&result, .channels.toSlice(), pixels, firstY, rows, .yMin)
        }

        return result
    }
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        if buffer.count < 9 or readU32(buffer.buffer) != Magic do
            fail InvalidFormatError{"OpenEXR signature or header is truncated"}
        let version = readU32(buffer.buffer + 4)
        if (version & 0xFF) != 2 do
            fail UnsupportedFormatError{"OpenEXR file version is not 2"}
        if version & 0xA00 do
            fail UnsupportedFormatError{"tiled and deep OpenEXR images are not supported"}
        .multipart = (version & 0x1000) != 0
        .bytes     = buffer
        .parts.clear()
        var offset = 8'u64
        var result: retval
        for
        {
            options.checkFrameCount(.parts.count + 1)
            var part = Part.parse(buffer, &offset, .multipart, options)
            result.frames.add(part.info)
            .parts.add(#move part)
            if !.multipart do
                break
            if offset >= buffer.count do
                fail InvalidFormatError{"OpenEXR part headers are not terminated"}
            if !buffer[offset]
            {
                offset += 1
                break
            }
        }

        for &part in .parts
        {
            if part.chunkCount > (buffer.count - offset) / 8 do
                fail InvalidFormatError{"OpenEXR chunk offset table is truncated"}
            part.tableOffset = offset
            offset           += part.chunkCount * 8
        }

        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .parts.count do
            fail InvalidFormatError{"OpenEXR part index is out of range"}
        return .parts[index].decode(.bytes!, index, .multipart, options)
    }
}

impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"EXR - OpenEXR", ".exr"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        let multiple: IImageSetDecoder = me
        discard multiple.open(buffer, options)
        return multiple.readFrame(0, options)
    }
}
