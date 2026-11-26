//! Format: Adobe Photoshop document decoder.
//! Supported: PSD version 1 composite images and raster layers in RGB or grayscale, at 8 or 16 bits,
//!            with raw or PackBits channel data and an optional alpha channel.
//! Not supported: PSB, indexed/CMYK/Lab color, layer effects, spot channels, or ZIP composites.
//! Role: This file imports the flattened composite that image viewers conventionally display.
//
#global namespace Psd

using Core, Core.Errors, Core.Math

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
func readU16(source: const [*] u8)->u16 => (cast(u16, source[0]) << 8) | source[1]

#[Swag.Inline]
func readU32(source: const [*] u8)->u32
{
    return (cast(u32, source[0]) << 24) |
           (cast(u32, source[1]) << 16) |
           (cast(u32, source[2]) << 8) |
           cast(u32, source[3])
}

func skipSection(buffer: const [..] u8, offset: *u64) fail
{
    if offset[] + 4 > buffer.count do
        fail InvalidFormatError{"PSD section length is truncated"}
    let size = cast(u64, readU32(buffer.buffer + offset[]))
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
        let control = cast #bit (s8, source[input])
        input += 1
        if control >= 0
        {
            let count = cast(u64, control) + 1
            if count > source.count - input or count > expected - output do
                fail InvalidFormatError{"PSD PackBits literal exceeds its row"}
            Memory.copy(destination + output, source.buffer + input, count)
            input  += count
            output += count
        }
        elif control != -128
        {
            let count = cast(u64, (1 - cast(s32, control)))
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

func storeChannel(image: *Image, channel: u16, sourceY: s32, source: const [*] u8, depth: u16)
{
    let targetY = image.height - sourceY - 1
    let row     = image.pixels.storage() + cast(u64, targetY) * image.rowStride
    let stride  = image.bytesPerPixel
    if depth == 8
    {
        var target = row + channel
        for x in image.width
        {
            target[0] = source[x]
            target   += stride
        }
    }
    else
    {
        let samples = cast(const [*] u16, source)
        var target  = row + cast(u64, channel) * 2
        for x in image.width
        {
            cast([*] u16, target)[0] = Math.byteSwap(samples[x])
            target += stride
        }
    }
}

#[Swag.Inline]
func loadBigEndianWords(source: const [*] u8)->Simd.U16x8
{
    let samples = Simd.load(cast(const [*] u16, source))
    return (samples >> 8) | (samples << 8)
}

func copyBigEndianWords(target: [*] u8, source: const [*] u8, count: u64)
{
    let words = cast([*] u16, target)
    var x: u64
    while count - x >= 8
    {
        Simd.store(words + x, loadBigEndianWords(source + x * 2))
        x += 8
    }

    while x < count
    {
        words[x] = readU16(source + x * 2)
        x        += 1
    }
}

private func(CHANNELS: u64) storeWordRow(destination: [*] u8, first: const [*] u8, width, planeBytes: u64)
{
    let second = first + planeBytes
    let third  = second + planeBytes
    let fourth = third + planeBytes
    var target = cast([*] u16, destination)
    var x: u64
    while width - x >= 8
    {
        let offset = x * 2
        let a      = loadBigEndianWords(first + offset)
        let b      = loadBigEndianWords(second + offset)
        #static if CHANNELS == 2
        {
            Simd.store(target, Simd.interleaveLow(a, b))
            Simd.store(target + 8, Simd.interleaveHigh(a, b))
        }
        else
        {
            let p0  = cast #bit(Simd.U8x16, a)
            let p1  = cast #bit(Simd.U8x16, b)
            let p2  = cast #bit(Simd.U8x16, loadBigEndianWords(third + offset))
            let dst = cast([*] u8, target)
            #static if CHANNELS == 3 do
                PackedPixel.storeTriplets'2(dst, p0, p1, p2)
            else
            {
                let p3 = cast #bit(Simd.U8x16, loadBigEndianWords(fourth + offset))
                PackedPixel.storeQuads'(Simd.U16x8, Simd.U32x4)(dst, p0, p1, p2, p3)
            }
        }

        target += 8 * CHANNELS
        x      += 8
    }

    for sample in x until width
    {
        let offset = sample * 2
        target[0] = readU16(first + offset)
        target[1] = readU16(second + offset)
        #static if CHANNELS >= 3 do
            target[2] = readU16(third + offset)
        #static if CHANNELS == 4 do
            target[3] = readU16(fourth + offset)
        target += CHANNELS
    }
}

private func(CHANNELS: u64) storeByteRow(destination: [*] u8, first: const [*] u8, width, planeBytes: u64)
{
    let second = first + planeBytes
    let third  = second + planeBytes
    let fourth = third + planeBytes
    var x: u64
    while width - x >= 16
    {
        let a = Simd.load(first + x)
        let b = Simd.load(second + x)
        let target = destination + x * CHANNELS
        #static if CHANNELS == 2
        {
            Simd.store(target, Simd.interleaveLow(a, b))
            Simd.store(target + 16, Simd.interleaveHigh(a, b))
        }
        elif CHANNELS == 3
        {
            PackedPixel.storeTriplets16(target, a, b, Simd.load(third + x))
        }
        else
        {
            PackedPixel.storeQuads16(target, a, b, Simd.load(third + x), Simd.load(fourth + x))
        }

        x += 16
    }

    for i in x until width
    {
        let target = destination + i * CHANNELS
        target[0] = first[i]
        target[1] = second[i]
        #static if CHANNELS >= 3 do
            target[2] = third[i]
        #static if CHANNELS == 4 do
            target[3] = fourth[i]
    }
}

private func storeCompositeRow(image: *Image, y: s32, source: const [*] u8, planeBytes: u64)
{
    let target = image.pixels.storage() + cast(u64, (image.height - y - 1)) * image.rowStride
    let width  = cast(u64, image.width)
    switch image.pixelFormat
    {
    case .Gray8:       Memory.copy(target, source, width)
    case .Gray16:      copyBigEndianWords(target, source, width)
    case .GrayAlpha8:  storeByteRow'2(target, source, width, planeBytes)
    case .GrayAlpha16: storeWordRow'2(target, source, width, planeBytes)
    case .RGB8:        storeByteRow'3(target, source, width, planeBytes)
    case .RGB16:       storeWordRow'3(target, source, width, planeBytes)
    case .RGBA8:       storeByteRow'4(target, source, width, planeBytes)
    case .RGBA16:      storeWordRow'4(target, source, width, planeBytes)
    default:          unreachable
    }
}

func storeRawComposite(image: *Image, source: const [*] u8, rowBytes: u64)
{
    let planeBytes = rowBytes * cast(u64, image.height)
    for y in image.height do
        storeCompositeRow(image, y, source + cast(u64, y) * rowBytes, planeBytes)
}

private func decodePackedComposite(image: *Image, buffer: const [..] u8, rowLengths: const [*] u8, offset, rowBytes: u64, channels: u16) fail
{
    let visible = cast(u64, image.pixelFormat.channels())
    let height = cast(u64, image.height)
    // Index the planar data once, then reconstruct one row across the visible channels.
    var cursors: [4] u64
    var end = offset
    for channel in visible
    {
        cursors[channel] = end
        for y in height
        {
            let size = cast(u64, readU16(rowLengths + (channel * height + y) * 2))
            if size > buffer.count - end do
                fail InvalidFormatError{"PSD PackBits row is truncated"}
            end += size
        }
    }

    var planes: Array'u8
    planes.reserve(rowBytes * visible)
    let rows = planes.storage()
    for y in height
    {
        for channel in visible
        {
            let size = cast(u64, readU16(rowLengths + (channel * height + y) * 2))
            let at = cursors[channel]
            try decodePackBits(rows + rowBytes * channel, rowBytes, Swag.makeSlice(buffer.buffer + at, size))
            cursors[channel] += size
        }

        storeCompositeRow(image, cast(s32, y), rows, rowBytes)
    }

    // Validate the remaining channel data even though the output does not store those channels.
    for channel in visible until channels
    {
        for y in height
        {
            let size = cast(u64, readU16(rowLengths + (channel * height + y) * 2))
            if size > buffer.count - end do
                fail InvalidFormatError{"PSD PackBits row is truncated"}
            try decodePackBits(rows, rowBytes, Swag.makeSlice(buffer.buffer + end, size))
            end += size
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
        if width == 0 or
           height == 0 or
           width > cast(u32, Swag.S32.Max) or
           height > cast(u32, Swag.S32.Max) do
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

        let bytesPerPixel = format.bitsPerPixel() / 8
        if width > cast(u32, Swag.S32.Max) / bytesPerPixel do
            fail UnsupportedFormatError{"PSD image row exceeds the image limits"}
        try options.checkImage(cast(s32, width), cast(s32, height), format)

        var result: #returntype
        result.init(cast(s32, width), cast(s32, height), format)
        if not options.decodePixels do
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

        let rowBytes = cast(u64, width) * (depth / 8)
        if rowBytes > Swag.U32.Max or cast(u64, channels) * height > Swag.U64.Max / rowBytes do
            fail UnsupportedFormatError{"PSD composite is too large"}

        let rowCount = cast(u64, channels) * height
        if compression == 0
        {
            if rowCount * rowBytes > buffer.count - offset do
                fail InvalidFormatError{"PSD raw composite is truncated"}
            result.allocPixels()
            storeRawComposite(&result, source + offset, rowBytes)
            return result
        }

        if rowCount > (buffer.count - offset) / 2 do
            fail InvalidFormatError{"PSD PackBits row table is truncated"}
        let rowLengths = source + offset
        offset += rowCount * 2

        result.allocPixels()
        try decodePackedComposite(&result, buffer, rowLengths, offset, rowBytes, channels)

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
        let signedCount = cast(s32, cast #bit(s16, readU16(buffer.buffer)))
        let count       = cast(u32, Math.abs(signedCount))
        try options.checkFrameCount(cast(u64, count) + 1)
        var offset = 2'u64
        for index in count
        {
            if buffer.count - offset < 18 do
                fail InvalidFormatError{"PSD layer record is truncated"}
            let top      = cast #bit(s32, readU32(buffer.buffer + offset))
            let left     = cast #bit(s32, readU32(buffer.buffer + offset + 4))
            let bottom   = cast #bit(s32, readU32(buffer.buffer + offset + 8))
            let right    = cast #bit(s32, readU32(buffer.buffer + offset + 12))
            let channels = readU16(buffer.buffer + offset + 16)
            offset += 18
            let width  = cast(s64, right) - left
            let height = cast(s64, bottom) - top
            if width < 0 or height < 0 or width > Swag.S32.Max or height > Swag.S32.Max do
                fail InvalidFormatError{"PSD layer dimensions are invalid"}
            if cast(u64, channels) * 6 + 16 > buffer.count - offset do
                fail InvalidFormatError{"PSD layer channels are truncated"}
            var layer:  Layer
            var format: PixelFormat
            if .colorMode == 1
            {
                format = .depth == 16 ? .GrayAlpha16 : .GrayAlpha8
            }
            else
            {
                format = .depth == 16 ? .RGBA16 : .RGBA8
            }

            layer.info = {kind: .Layer, width: cast(s32, width), height: cast(s32, height), x: left, y: top, pixelFormat: format, layer: index}
            if width and height do
                try options.checkImage(layer.info.width, layer.info.height, format)
            for channels
            {
                layer.channels.add({id: cast #bit(s16, readU16(buffer.buffer + offset)), length: readU32(buffer.buffer + offset + 2)})
                offset += 6
            }

            if readU32(buffer.buffer + offset) != 0x3842494D do
                fail InvalidFormatError{"PSD layer blend signature is invalid"}
            let extraLength = cast(u64, readU32(buffer.buffer + offset + 12))
            offset += 16
            if extraLength > buffer.count - offset do
                fail InvalidFormatError{"PSD layer extra data is truncated"}
            let extra       = buffer[offset until offset + extraLength]
            var extraOffset = 0'u64
            try skipSection(extra, &extraOffset)
            try skipSection(extra, &extraOffset)
            if extraOffset >= extra.count do
                fail InvalidFormatError{"PSD layer name is truncated"}
            let nameLength = cast(u64, extra[extraOffset])
            if nameLength + 1 > extra.count - extraOffset do
                fail InvalidFormatError{"PSD layer name exceeds its record"}
            layer.info.name = cast(string, extra[extraOffset + 1 until extraOffset + 1 + nameLength])
            offset += extraLength
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
        var result: #returntype
        result.init(.info.width, .info.height, .info.pixelFormat)
        if not options.decodePixels do
            return result
        result.allocPixels()
        let rowBytes = cast(u64, result.width) * (depth / 8)
        let required = rowBytes * cast(u64, result.height)
        let alpha    = result.pixelFormat.isGrayscale() ? 1'u16 : 3'u16
        var present: u8
        for channel in .channels where channel.id >= -1 and channel.id < alpha
        {
            let component = channel.id == -1 ? alpha : cast(u16, channel.id)
            present |= 1'u8 << component
        }

        if present != (1'u8 << (alpha + 1)) - 1 do
            result.fill(Argb.Black)

        var rowScratch: Array'u8
        for channel in .channels
        {
            if channel.id < -1 or cast(s32, channel.id) >= cast(s32, alpha) do
                continue
            let component = channel.id == -1 ? alpha : cast(u16, channel.id)
            let bytes     = unwrap channel.bytes
            if bytes.count < 2 do
                fail InvalidFormatError{"PSD layer channel compression is missing"}
            let compression = readU16(bytes.buffer)
            var offset      = 2'u64
            var unpacked: Array'u8
            var pixels = bytes[offset to]
            if compression == 0
            {
                if bytes.count - offset != required do
                    fail InvalidFormatError{"PSD raw layer channel has an invalid size"}
            }
            elif compression == 1
            {
                let tableBytes = cast(u64, result.height) * 2
                if tableBytes > bytes.count - offset do
                    fail InvalidFormatError{"PSD layer row table is truncated"}
                offset += tableBytes
                rowScratch.reserve(rowBytes)
                let row = rowScratch.storage()
                for y in result.height
                {
                    let length = cast(u64, readU16(bytes.buffer + 2 + cast(u64, y) * 2))
                    if length > bytes.count - offset do
                        fail InvalidFormatError{"PSD compressed layer row is truncated"}
                    try decodePackBits(row, rowBytes, bytes[offset until offset + length])
                    storeChannel(&result, component, y, row, depth)
                    offset += length
                }

                if offset != bytes.count do
                    fail InvalidFormatError{"PSD layer channel has trailing bytes"}
                continue
            }
            elif compression == 2 or compression == 3
            {
                var zlib: Compress.ZLib
                unpacked = try zlib.decompress(pixels, required)
                if unpacked.count != required do
                    fail InvalidFormatError{"PSD ZIP layer channel has an invalid decoded size"}
                if compression == 3
                {
                    for y in result.height
                    {
                        let row = unpacked.storage() + cast(u64, y) * rowBytes
                        for x in range(1, result.width)
                        {
                            if depth == 8
                            {
                                row[x] = cast(u8, ((cast(u32, row[x]) + row[x - 1]) & 255))
                            }
                            else
                            {
                                let sample = (cast(u32, readU16(row + cast(u64, x) * 2)) + readU16(row + cast(u64, (x - 1)) * 2)) & 65535
                                row[cast(u64, x) * 2]     = cast(u8, (sample >> 8))
                                row[cast(u64, x) * 2 + 1] = cast(u8, (sample & 255))
                            }
                        }
                    }
                }
                pixels = unpacked.toSlice()
            }
            else
            {
                fail UnsupportedFormatError{"PSD layer compression is not supported"}
            }

            for y in result.height do
                storeChannel(&result, component, y, pixels.buffer + cast(u64, y) * rowBytes, depth)
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
        let probe = try single.decode(buffer, probeOptions)
        .depth     = readU16(buffer.buffer + 22)
        .colorMode = readU16(buffer.buffer + 24)
        var result: #returntype
        result.frames.add({width: probe.width, height: probe.height, pixelFormat: probe.pixelFormat, name: String.from("Composite")})
        var offset = HeaderSize
        try skipSection(buffer, &offset)
        try skipSection(buffer, &offset)
        if buffer.count - offset < 4 do
            fail InvalidFormatError{"PSD layer section is truncated"}
        let sectionLength = cast(u64, readU32(buffer.buffer + offset))
        offset += 4
        if sectionLength > buffer.count - offset do
            fail InvalidFormatError{"PSD layer section exceeds the file"}
        if not sectionLength do
            return result
        let section = buffer[offset until offset + sectionLength]
        if section.count < 4 do
            fail InvalidFormatError{"PSD layer information length is truncated"}
        let layerLength = cast(u64, readU32(section.buffer))
        if layerLength > section.count - 4 do
            fail InvalidFormatError{"PSD layer information exceeds its section"}
        if layerLength do
            try .indexLayers(section[4 until 4 + layerLength], options)
        var tail = 4 + layerLength
        if tail < section.count
        {
            try skipSection(section, &tail)
            while section.count - tail >= 12
            {
                let key  = readU32(section.buffer + tail + 4)
                let size = cast(u64, readU32(section.buffer + tail + 8))
                tail += 12
                if size > section.count - tail do
                    fail InvalidFormatError{"PSD additional layer block is truncated"}
                if key == 0x4C723136 and .depth == 16 do
                    try .indexLayers(section[tail until tail + size], options)
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
                .imageLayers.add(cast(u32, index))
            }
        }

        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if not index
        {
            let single: IImageDecoder = me
            return try single.decode(unwrap .bytes, options)
        }

        if index > .imageLayers.count do
            fail InvalidFormatError{"PSD layer index is out of range"}
        return try .layers[.imageLayers[index - 1]].decode(.depth, options)
    }
}
