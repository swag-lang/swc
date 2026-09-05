//! Format: Adobe Photoshop document decoder.
//! Supported: PSD version 1 composite images and raster layers in RGB or grayscale, at 8 or 16 bits,
//!            with raw or PackBits channel data and an optional alpha channel.
//! Not supported: PSB, indexed/CMYK/Lab color, layer effects, spot channels, or ZIP composites.
//! Role: This file imports the flattened composite that image viewers conventionally display.
//
#global namespace Psd

using Core, Core.Errors

const HeaderSize = 26'u64

internal struct Decoder
{
    bytes:       const [..] u8?
    layers:      Array'Layer
    imageLayers: Array'u32
    depth:       u16
    colorMode:   u16
}

struct LayerChannel
{
    id:     s16
    length: u32
    bytes:  const [..] u8?
}

struct Layer
{
    info:     ImageFrameInfo
    channels: Array'LayerChannel
}

#[Swag.Inline]
func readU16(source: const [*] u8)->u16
{
    return (cast(u16) source[0] << 8) | source[1]
}

#[Swag.Inline]
func readU32(source: const [*] u8)->u32
{
    return (cast(u32) source[0] << 24) |
           (cast(u32) source[1] << 16) |
           (cast(u32) source[2] << 8) |
           cast(u32) source[3]
}

func skipSection(buffer: const [..] u8, offset: *u64) fail
{
    if offset[] + 4 > buffer.count do
        fail InvalidFormatError{"PSD section length is truncated"}
    let size = cast(u64) readU32(buffer.buffer + offset[])
    offset[] += 4
    if size > buffer.count - offset[] do
        fail InvalidFormatError{"PSD section exceeds the file"}
    offset[] += size
}

func decodePackBits(destination: [*] u8, expected: u64, source: const [..] u8) fail
{
    var input  = 0'u64
    var output = 0'u64
    while input < source.count and output < expected
    {
        let control = cast #bit (s8) source[input]
        input += 1
        if control >= 0
        {
            let count = cast(u64) control + 1
            if count > source.count - input or count > expected - output do
                fail InvalidFormatError{"PSD PackBits literal exceeds its row"}
            Memory.copy(destination + output, source.buffer + input, count)
            input  += count
            output += count
        }
        elif control != -128
        {
            let count = cast(u64) (1 - cast(s32) control)
            if input >= source.count or count > expected - output do
                fail InvalidFormatError{"PSD PackBits run exceeds its row"}
            Memory.set(destination + output, source[input], count)
            input  += 1
            output += count
        }
    }

    if output != expected or input != source.count do
        fail InvalidFormatError{"PSD PackBits row has an invalid decoded length"}
}

func storeChannel(image: *Image, channel: u16, sourceY: s32, source: const [..] u8, depth: u16)
{
    let alphaChannel = image.pixelFormat.isGrayscale() ? 1'u16 : 3'u16
    if channel >= image.pixelFormat.channels() or channel > alphaChannel do
        return

    let targetY = image.height - sourceY - 1
    var target  = image.pixels.buffer! + cast(u64) targetY * image.rowStride
    if depth == 8
    {
        for x in image.width
        {
            target[channel] = source[x]
            target          += image.bytesPerPixel
        }
    }
    else
    {
        for x in image.width
        {
            let sourceOffset = cast(u64) x * 2
            let sample       = (cast(u16) source[sourceOffset] << 8) | cast(u16) source[sourceOffset + 1]
            (target + cast(u64) channel * 2)[as u16] = sample
            target += image.bytesPerPixel
        }
    }
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"PSD - Adobe Photoshop Document", ".psd"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        if buffer.count < HeaderSize do
            fail InvalidFormatError{"PSD header is truncated"}
        let source = buffer.buffer
        if source[0] != '8' or source[1] != 'B' or source[2] != 'P' or source[3] != 'S' do
            fail InvalidFormatError{"PSD signature is invalid"}
        if readU16(source + 4) != 1 do
            fail UnsupportedFormatError{"only PSD version 1 files are supported"}
        for i in 6 where source[6 + i] do
            fail InvalidFormatError{"PSD reserved header bytes must be zero"}

        let channels  = readU16(source + 12)
        let height    = readU32(source + 14)
        let width     = readU32(source + 18)
        let depth     = readU16(source + 22)
        let colorMode = readU16(source + 24)
        if width == 0 or height == 0 or width > cast(u32) Swag.S32.Max or height > cast(u32) Swag.S32.Max do
            fail UnsupportedFormatError{"PSD dimensions exceed the image limits"}
        if depth != 8 and depth != 16 do
            fail UnsupportedFormatError{"PSD composite depth must be 8 or 16 bits"}

        var format: PixelFormat
        switch colorMode
        {
        case 1:
            if channels < 1 do
                fail InvalidFormatError{"grayscale PSD data has no channel"}
            if depth == 8 do
                format = channels >= 2 ? .GrayAlpha8 : .Gray8
            else do
                format = channels >= 2 ? .GrayAlpha16 : .Gray16

        case 3:
            if channels < 3 do
                fail InvalidFormatError{"RGB PSD data has fewer than three channels"}
            if depth == 8 do
                format = channels >= 4 ? .RGBA8 : .RGB8
            else do
                format = channels >= 4 ? .RGBA16 : .RGB16

        default:
            fail UnsupportedFormatError{"PSD color mode is not RGB or grayscale"}
        }

        var result: retval
        result.init(cast(s32) width, cast(s32) height, format)
        options.checkImage(result.width, result.height, format)
        if !options.decodePixels do
            return result

        var offset = HeaderSize
        try skipSection(buffer, &offset)     // Color-mode data.
        try skipSection(buffer, &offset)     // Image resources.
        try skipSection(buffer, &offset)     // Layer and mask information.
        if offset + 2 > buffer.count do
            fail InvalidFormatError{"PSD composite compression is missing"}
        let compression = readU16(source + offset)
        offset += 2
        if compression > 1 do
            fail UnsupportedFormatError{"PSD composite compression must be raw or PackBits"}

        let rowBytes = cast(u64) width * (depth / 8)
        if rowBytes > Swag.U32.Max or cast(u64) channels * height > Swag.U64.Max / rowBytes do
            fail UnsupportedFormatError{"PSD composite is too large"}
        result.allocPixels()
        result.clear()

        var rowLengths: Array'u16
        if compression == 1
        {
            let rowCount = cast(u64) channels * height
            if rowCount > (buffer.count - offset) / 2 do
                fail InvalidFormatError{"PSD PackBits row table is truncated"}
            rowLengths.resize(rowCount)
            for i in rowCount
            {
                rowLengths[i] = readU16(source + offset)
                offset        += 2
            }
        }

        var row: Array'u8
        row.resize(rowBytes)
        for channel in channels
        {
            for y in cast(s32) height
            {
                if compression == 0
                {
                    if rowBytes > buffer.count - offset do
                        fail InvalidFormatError{"PSD raw composite is truncated"}
                    Memory.copy(row.buffer, source + offset, rowBytes)
                    offset += rowBytes
                }
                else
                {
                    let encodedSize = cast(u64) rowLengths[cast(u64) channel * height + cast(u64) y]
                    if encodedSize > buffer.count - offset do
                        fail InvalidFormatError{"PSD PackBits row is truncated"}
                    try decodePackBits(row.buffer!, rowBytes, Swag.makeSlice(source + offset, encodedSize))
                    offset += encodedSize
                }

                storeChannel(&result, channel, y, row.toSlice(), depth)
            }
        }

        return result
    }
}

impl Decoder
{
    mtd indexLayers(buffer: const [..] u8, options: DecodeOptions) fail
    {
        .layers.clear()
        if buffer.count < 2 do
            fail InvalidFormatError{"PSD layer count is truncated"}
        let signedCount = cast(s32) cast #bit(s16) readU16(buffer.buffer)
        let count       = cast(u32) Math.abs(signedCount)
        options.checkFrameCount(cast(u64) count + 1)
        var offset = 2'u64
        for index in count
        {
            if buffer.count - offset < 18 do
                fail InvalidFormatError{"PSD layer record is truncated"}
            let top      = cast #bit(s32) readU32(buffer.buffer + offset)
            let left     = cast #bit(s32) readU32(buffer.buffer + offset + 4)
            let bottom   = cast #bit(s32) readU32(buffer.buffer + offset + 8)
            let right    = cast #bit(s32) readU32(buffer.buffer + offset + 12)
            let channels = readU16(buffer.buffer + offset + 16)
            offset += 18
            let width  = cast(s64) right - left
            let height = cast(s64) bottom - top
            if width < 0 or height < 0 or width > Swag.S32.Max or height > Swag.S32.Max do
                fail InvalidFormatError{"PSD layer dimensions are invalid"}
            if cast(u64) channels * 6 + 16 > buffer.count - offset do
                fail InvalidFormatError{"PSD layer channels are truncated"}
            var layer:  Layer
            let format: PixelFormat = .colorMode == 1 ? (.depth == 16 ? .GrayAlpha16 : .GrayAlpha8) : (.depth == 16 ? .RGBA16 : .RGBA8)
            layer.info = {kind: .Layer, width: cast(s32) width, height: cast(s32) height, x: left, y: top, pixelFormat: format, layer: index}
            if width and height do
                options.checkImage(layer.info.width, layer.info.height, format)
            for channels
            {
                layer.channels.add({id: cast #bit(s16) readU16(buffer.buffer + offset), length: readU32(buffer.buffer + offset + 2)})
                offset += 6
            }

            if readU32(buffer.buffer + offset) != 0x3842494D do
                fail InvalidFormatError{"PSD layer blend signature is invalid"}
            let extraLength = cast(u64) readU32(buffer.buffer + offset + 12)
            offset += 16
            if extraLength > buffer.count - offset do
                fail InvalidFormatError{"PSD layer extra data is truncated"}
            let extra       = buffer[offset until offset + extraLength]
            var extraOffset = 0'u64
            skipSection(extra, &extraOffset)
            skipSection(extra, &extraOffset)
            if extraOffset >= extra.count do
                fail InvalidFormatError{"PSD layer name is truncated"}
            let nameLength = cast(u64) extra[extraOffset]
            if nameLength + 1 > extra.count - extraOffset do
                fail InvalidFormatError{"PSD layer name exceeds its record"}
            layer.info.name = cast(string) extra[extraOffset + 1 until extraOffset + 1 + nameLength]
            offset          += extraLength
            .layers.add(#move layer)
        }

        for &layer in .layers
        {
            for &channel in layer.channels
            {
                if channel.length > buffer.count - offset do
                    fail InvalidFormatError{"PSD layer channel data is truncated"}
                channel.bytes = buffer[offset until offset + channel.length]
                offset        += channel.length
            }
        }
    }
}

impl Layer
{
    mtd decode(depth: u16, options: DecodeOptions)->Image fail
    {
        var result: retval
        result.init(.info.width, .info.height, .info.pixelFormat)
        if !options.decodePixels do
            return result
        result.allocPixels()
        result.fill(Argb.Black)
        let rowBytes = cast(u64) result.width * (depth / 8)
        let required = rowBytes * cast(u64) result.height
        let alpha    = result.pixelFormat.isGrayscale() ? 1'u16 : 3'u16
        for channel in .channels
        {
            if channel.id < -1 or cast(s32) channel.id >= cast(s32) alpha do
                continue
            let component = channel.id == -1 ? alpha : cast(u16) channel.id
            let bytes     = channel.bytes!
            if bytes.count < 2 do
                fail InvalidFormatError{"PSD layer channel compression is missing"}
            let compression = readU16(bytes.buffer)
            var offset      = 2'u64
            var pixels: Array'u8
            if compression == 0
            {
                if bytes.count - offset != required do
                    fail InvalidFormatError{"PSD raw layer channel has an invalid size"}
                pixels.add(bytes[offset to])
            }
            elif compression == 1
            {
                let tableBytes = cast(u64) result.height * 2
                if tableBytes > bytes.count - offset do
                    fail InvalidFormatError{"PSD layer row table is truncated"}
                offset += tableBytes
                pixels.resize(required)
                for y in result.height
                {
                    let length = cast(u64) readU16(bytes.buffer + 2 + cast(u64) y * 2)
                    if length > bytes.count - offset do
                        fail InvalidFormatError{"PSD compressed layer row is truncated"}
                    decodePackBits(pixels.buffer! + cast(u64) y * rowBytes, rowBytes, bytes[offset until offset + length])
                    offset += length
                }

                if offset != bytes.count do
                    fail InvalidFormatError{"PSD layer channel has trailing bytes"}
            }
            elif compression == 2 or compression == 3
            {
                var zlib: Compress.ZLib
                pixels = zlib.decompress(bytes[offset to], required)
                if pixels.count != required do
                    fail InvalidFormatError{"PSD ZIP layer channel has an invalid decoded size"}
                if compression == 3
                {
                    for y in result.height
                    {
                        let row = pixels.buffer! + cast(u64) y * rowBytes
                        for x in range(1, result.width)
                        {
                            if depth == 8 do
                                row[x] = cast(u8) ((cast(u32) row[x] + row[x - 1]) & 255)
                            else
                            {
                                let sample = (cast(u32) readU16(row + cast(u64) x * 2) + readU16(row + cast(u64) (x - 1) * 2)) & 65535
                                row[cast(u64) x * 2]     = cast(u8) (sample >> 8)
                                row[cast(u64) x * 2 + 1] = cast(u8) (sample & 255)
                            }
                        }
                    }
                }
            }
            else do
                fail UnsupportedFormatError{"PSD layer compression is not supported"}
            for y in result.height do
                storeChannel(&result, component, y, Swag.makeSlice(pixels.buffer! + cast(u64) y * rowBytes, rowBytes), depth)
        }

        return result
    }
}

impl IImageSetDecoder for Decoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .bytes = buffer
        .layers.clear()
        .imageLayers.clear()
        var probeOptions = options
        probeOptions.decodePixels = false
        let single: IImageDecoder = me
        let probe                 = single.decode(buffer, probeOptions)
        .depth     = readU16(buffer.buffer + 22)
        .colorMode = readU16(buffer.buffer + 24)
        var result: retval
        result.frames.add({width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat, name: String.from("Composite")})
        var offset = HeaderSize
        skipSection(buffer, &offset)
        skipSection(buffer, &offset)
        if buffer.count - offset < 4 do
            fail InvalidFormatError{"PSD layer section is truncated"}
        let sectionLength = cast(u64) readU32(buffer.buffer + offset)
        offset += 4
        if sectionLength > buffer.count - offset do
            fail InvalidFormatError{"PSD layer section exceeds the file"}
        if !sectionLength do
            return result
        let section = buffer[offset until offset + sectionLength]
        if section.count < 4 do
            fail InvalidFormatError{"PSD layer information length is truncated"}
        let layerLength = cast(u64) readU32(section.buffer)
        if layerLength > section.count - 4 do
            fail InvalidFormatError{"PSD layer information exceeds its section"}
        if layerLength do
            .indexLayers(section[4 until 4 + layerLength], options)
        var tail = 4 + layerLength
        if tail < section.count
        {
            skipSection(section, &tail)
            while section.count - tail >= 12
            {
                let key  = readU32(section.buffer + tail + 4)
                let size = cast(u64) readU32(section.buffer + tail + 8)
                tail += 12
                if size > section.count - tail do
                    fail InvalidFormatError{"PSD additional layer block is truncated"}
                if key == 0x4C723136 and .depth == 16 do
                    .indexLayers(section[tail until tail + size], options)
                tail += size + (size & 1)
                if tail > section.count do
                    fail InvalidFormatError{"PSD additional layer padding is truncated"}
            }
        }

        for index in .layers.count
        {
            let layer = &.layers[index]
            if layer.info.width and layer.info.height
            {
                result.frames.add(layer.info)
                .imageLayers.add(cast(u32) index)
            }
        }

        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if !index
        {
            let single: IImageDecoder = me
            return single.decode(.bytes!, options)
        }

        if index > .imageLayers.count do
            fail InvalidFormatError{"PSD layer index is out of range"}
        return .layers[.imageLayers[index - 1]].decode(.depth, options)
    }
}
