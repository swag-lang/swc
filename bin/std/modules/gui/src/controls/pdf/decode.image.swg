#global namespace Pdf

using Core, Core.Errors, Core.Math, Pixel

// Decoding of image XObjects and inline images.
//
// Every sample representation a PDF may use for a raster - one to sixteen bits per
// component, indexed palettes, device and calibrated color spaces, decode arrays, stencil
// and soft masks - is expanded here into a Pixel image. Only the self-contained image
// codecs are delegated, and only to Pixel's own decoders.

// The families a color space reduces to once its calibration is applied.
enum ImageSpaceKind
{
    Gray
    Rgb
    Cmyk
    Lab
    Indexed
    Subtractive     // Separation and DeviceN, approximated by their darkest tint.
}

struct ImageSpace
{
    kind:           ImageSpaceKind = ImageSpaceKind.Gray
    components:     u32            = 1
    baseKind:       ImageSpaceKind = ImageSpaceKind.Rgb
    baseComponents: u32            = 3
    palette:        Array'u8
    hival:          u32
    range:          [4] f32        = [-100, 100, -100, 100]

    // The space could not be reduced to a color — a pattern, or an unresolvable name. A mark
    // painted with it is dropped rather than painted in a color the stream never asked for:
    // a gradient-filled chart region must not become an opaque black rectangle.
    unsupported: bool
}

// One decoded raster, in top-left-first row order, before it becomes a Pixel image.
private struct SamplePlane
{
    rgb:    Array'u8     // Three bytes per pixel.
    alpha:  Array'u8     // Empty when the image is fully opaque, one byte per pixel otherwise.
    width:  s32
    height: s32
}

func componentByte(value: f32)->u8 => cast(u8) Math.clamp(Math.round(value * 255.0), 0, 255)

func grayColor(value: f64)->Color
{
    let level = componentByte(cast(f32) value)
    return Color.fromRgb(level, level, level)
}

func rgbColor(r, g, b: f64)->Color => Color.fromRgb(componentByte(cast(f32) r), componentByte(cast(f32) g), componentByte(cast(f32) b))

func cmykColor(c, m, y, k: f64)->Color
{
    var target: [3] u8
    cmykToRgb(cast(f32) c, cast(f32) m, cast(f32) y, cast(f32) k, target)
    return Color.fromRgb(target[0], target[1], target[2])
}

// Returns the color space a device operator such as `rg` or `k` selects.
func deviceSpace(kind: ImageSpaceKind, components: u32)->ImageSpace
{
    var result: retval
    result.kind       = kind
    result.components = components
    return result
}

// Returns the color a space starts at when it becomes current, which the format defines as
// black for every space this module supports.
func initialSpaceColor(space: const *ImageSpace)->Color
{
    let count = Math.min(space.components, 8'u32)
    var values: [8] f32
    if space.kind == .Subtractive
    {
        for i in count do
            values[i] = 1
    }
    elif space.kind == .Cmyk and count == 4 do
        values[3] = 1

    return spaceColor(space, values[0 until count])
}

// Turns the operands of `sc` or `scn` into a color.
//
// An operator may carry fewer operands than its space declares; the missing ones stay at zero
// instead of reading whatever the previous color left behind.
func spaceColor(space: const *ImageSpace, values: const [..] f32)->Color
{
    var operands: [8] f32
    for i in Math.min(@countof(values), 8'u64) do
        operands[i] = values[i]

    var target: [3] u8
    if space.kind != .Indexed
    {
        writeColor(space, space.kind, operands, target)
        return Color.fromRgb(target[0], target[1], target[2])
    }

    if !@countof(values) or !space.palette.count do
        return Color.fromArgb(Argb.Black)
    let index = cast(u64) Math.clamp(cast(s32) Math.round(operands[0]), 0, cast(s32) space.hival)
    let entry = index * cast(u64) space.baseComponents
    var base: [8] f32
    for i in Math.min(space.baseComponents, 8'u32) do
        base[i] = cast(f32) space.palette[entry + i] / 255.0

    var palette = space[]
    palette.components = space.baseComponents
    writeColor(&palette, space.baseKind, base, target)
    return Color.fromRgb(target[0], target[1], target[2])
}

// Returns one sample of a row, whatever the declared bit depth.
private func sampleAt(data: const [..] u8, rowBase: u64, index: u64, bits: u32)->u32
{
    switch bits
    {
    case 8:
        return data[rowBase + index]

    case 16:
        let offset = rowBase + index * 2
        return cast(u32) data[offset] << 8 | data[offset + 1]
    }

    let bit   = index * bits
    let byte  = data[rowBase + bit / 8]
    let shift = 8 - bits - cast(u32) (bit % 8)
    return (cast(u32) byte >> shift) & ((1'u32 << bits) - 1)
}

// Reduces a color space named by a `cs`, `CS`, or `/ColorSpace` entry.
//
// A name that is not a device space is defined by the resource dictionary in force, which is
// why the content stream cannot resolve one on its own.
func resolveNamedColorSpace(parser: *PdfParser, name: string, resourcesId: u32, depth: u32)->ImageSpace fail
{
    switch name
    {
    case "DeviceGray", "G", "CalGray": return deviceSpace(.Gray, 1)
    case "DeviceRGB", "RGB", "CalRGB": return deviceSpace(.Rgb, 3)
    case "DeviceCMYK", "CMYK":         return deviceSpace(.Cmyk, 4)
    case "Pattern":                    fail UnsupportedFormatError{"PDF pattern color spaces are not supported"}
    }

    let named = parser.dictRaw(parser.dict(resourcesId, "ColorSpace"), name)
    if named == InvalidNode do
        fail UnsupportedFormatError{"PDF color space is not supported"}
    return try resolveImageSpace(parser, named, resourcesId, depth + 1)
}

// Reduces a color space object, however it is spelled, to the family and component count
// the sample decoder and the color operators both work from.
func resolveImageSpace(parser: *PdfParser, spaceRaw, resourcesId: u32, depth: u32)->ImageSpace fail
{
    var result: retval
    if depth >= 8 do
        fail UnsupportedFormatError{"PDF color space nesting exceeds the supported depth"}

    let spaceId = parser.resolve(spaceRaw)
    if spaceId == InvalidNode
    {
        result.kind       = .Rgb
        result.components = 3
        return result
    }

    if parser.nodes[spaceId].kind == .Name do
        return try resolveNamedColorSpace(parser, parser.nodes[spaceId].text.toString(), resourcesId, depth)

    if parser.nodes[spaceId].kind != .Array or !parser.nodes[spaceId].values.count do
        fail UnsupportedFormatError{"PDF image color space is not supported"}

    let values = parser.nodes[spaceId].values
    let family = parser.name(values[0])
    switch family
    {
    case "ICCBased":

        // The profile itself is not applied; the component count decides the family.
        let stream = @countof(values) > 1 ? parser.resolve(values[1]) : InvalidNode
        let count  = parser.integer(parser.dict(stream, "N"), 3)
        switch count
        {
        case 1:
            result.kind       = .Gray
            result.components = 1

        case 4:
            result.kind       = .Cmyk
            result.components = 4

        default:
            result.kind       = .Rgb
            result.components = 3
        }

        return result

    case "CalRGB":
        result.kind       = .Rgb
        result.components = 3
        return result

    case "CalGray":
        result.kind       = .Gray
        result.components = 1
        return result

    case "Lab":
        result.kind       = .Lab
        result.components = 3
        let parameters = @countof(values) > 1 ? parser.resolve(values[1]) : InvalidNode
        let rangeId    = parser.dict(parameters, "Range")
        if rangeId != InvalidNode and parser.nodes[rangeId].kind == .Array and parser.nodes[rangeId].values.count >= 4
        {
            for i in 4'u64 do
                result.range[i] = cast(f32) parser.number(parser.nodes[rangeId].values[i])
        }

        return result

    case "Indexed", "I":
        if @countof(values) < 4 do
            fail InvalidFormatError{"PDF indexed color space is incomplete"}
        let base = try resolveImageSpace(parser, values[1], resourcesId, depth + 1)
        if base.kind == .Indexed do
            fail InvalidFormatError{"PDF indexed color space cannot index another one"}
        let hival = parser.integer(values[2])
        if hival < 0 or hival > 255 do
            fail InvalidFormatError{"PDF indexed color space has an invalid high value"}

        result.kind           = .Indexed
        result.components     = 1
        result.baseKind       = base.kind
        result.baseComponents = base.components
        result.range          = base.range
        result.hival          = cast(u32) hival

        let lookup = parser.resolve(values[3])
        if lookup == InvalidNode do
            fail InvalidFormatError{"PDF indexed color space has no lookup table"}
        if parser.nodes[lookup].kind == .String do
            result.palette = cast(const [..] u8) parser.nodes[lookup].text.toString()
        else do
            result.palette = try parser.decodeStream(lookup)

        let needed = cast(u64) (result.hival + 1) * cast(u64) base.components
        if result.palette.count < needed do
            fail InvalidFormatError{"PDF indexed color space lookup table is truncated"}
        return result

    case "Separation":
        result.kind       = .Subtractive
        result.components = 1
        return result

    case "DeviceN":
        let names = @countof(values) > 1 ? parser.resolve(values[1]) : InvalidNode
        if names == InvalidNode or parser.nodes[names].kind != .Array or !parser.nodes[names].values.count do
            fail InvalidFormatError{"PDF DeviceN color space names no colorants"}
        result.kind       = .Subtractive
        result.components = cast(u32) parser.nodes[names].values.count
        return result
    }

    fail UnsupportedFormatError{"PDF image color space is not supported"}
}

// Converts a CIE L*a*b* triple to sRGB, through the D50 white point PDF uses by default.
private func labToRgb(lightness, a, b: f32, target: [..] u8)
{
    let fy = (lightness + 16.0) / 116.0
    let fx = fy + a / 500.0
    let fz = fy - b / 200.0

    func expand(t: f32)->f32
    {
        const Limit = 6.0'f32 / 29.0
        return t > Limit ? t * t * t : 3.0 * Limit * Limit * (t - 4.0'f32 / 29.0)
    }

    let x = 0.9642 * expand(fx)
    let y = 1.0 * expand(fy)
    let z = 0.8249 * expand(fz)

    func gamma(value: f32)->f32
    {
        let clamped = Math.clamp(value, 0.0, 1.0)
        return clamped <= 0.0031308 ? 12.92 * clamped : 1.055 * Math.pow(clamped, 1.0 / 2.4) - 0.055
    }

    target[0] = componentByte(gamma(3.1339 * x - 1.6170 * y - 0.4906 * z))
    target[1] = componentByte(gamma(-0.9785 * x + 1.9160 * y + 0.0333 * z))
    target[2] = componentByte(gamma(0.0720 * x - 0.2290 * y + 1.4057 * z))
}

private func cmykToRgb(c, m, y, k: f32, target: [..] u8)
{
    target[0] = componentByte(1.0 - Math.min(1.0, c + k))
    target[1] = componentByte(1.0 - Math.min(1.0, m + k))
    target[2] = componentByte(1.0 - Math.min(1.0, y + k))
}

// Writes one pixel from already normalized components.
//
// `components` always carries the full working set, so a space whose operands were short still
// reads defined zeroes rather than the tail of an earlier color.
private func writeColor(space: const *ImageSpace, kind: ImageSpaceKind, components: const [8] f32, target: [..] u8)
{
    switch kind
    {
    case .Gray:
        target[0] = componentByte(components[0])
        target[1] = target[0]
        target[2] = target[0]

    case .Rgb:
        target[0] = componentByte(components[0])
        target[1] = componentByte(components[1])
        target[2] = componentByte(components[2])

    case .Cmyk:
        cmykToRgb(components[0], components[1], components[2], components[3], target)

    case .Lab:
        labToRgb(components[0], components[1], components[2], target)

    case .Subtractive:

        // Without evaluating the tint transform, the darkest colorant is the best neutral
        // approximation of the painted ink.
        var tint = 0.0'f32
        for i in Math.min(space.components, 8'u32) do
            tint = Math.max(tint, components[i])
        target[0] = componentByte(1.0 - tint)
        target[1] = target[0]
        target[2] = target[0]

    case .Indexed:
        break
    }
}

// Reads the samples of an image XObject into a top-down RGB plane.
private func readSamplePlane(parser: *PdfParser, nodeId, resourcesId: u32)->SamplePlane fail
{
    var result: retval
    let width  = parser.integer(parser.dict(nodeId, "Width"))
    let height = parser.integer(parser.dict(nodeId, "Height"))
    if width <= 0 or height <= 0 or width > Swag.S32.Max or height > Swag.S32.Max do
        fail InvalidFormatError{"PDF image has invalid dimensions"}
    result.width  = cast(s32) width
    result.height = cast(s32) height

    let bits = parser.integer(parser.dict(nodeId, "BitsPerComponent"), 8)
    if bits != 1 and bits != 2 and bits != 4 and bits != 8 and bits != 16 do
        fail UnsupportedFormatError{"PDF image bit depth is not supported"}
    let depth = cast(u32) bits

    let space      = try resolveImageSpace(parser, parser.dictRaw(nodeId, "ColorSpace"), resourcesId, 0)
    let bytes      = try parser.decodeStream(nodeId)
    let pixelCount = cast(u64) width * cast(u64) height
    let rowBytes   = (cast(u64) space.components * cast(u64) depth * cast(u64) width + 7) / 8
    if bytes.count < rowBytes * cast(u64) height do
        fail InvalidFormatError{"PDF image stream is truncated"}

    // `/Decode` remaps each raw sample onto the range the color space expects; every space
    // but Indexed and Lab defaults to zero through one.
    let maxValue = cast(f32) ((1'u64 << depth) - 1)
    var lowest:  [8] f32
    var highest: [8] f32
    let count    = Math.min(space.components, 8'u32)
    for i in count
    {
        lowest[i]  = 0
        highest[i] = 1
    }

    if space.kind == .Indexed do
        highest[0] = maxValue
    elif space.kind == .Lab
    {
        highest[0] = 100
        lowest[1]  = space.range[0]
        highest[1] = space.range[1]
        lowest[2]  = space.range[2]
        highest[2] = space.range[3]
    }

    let decodeId = parser.dict(nodeId, "Decode")
    if decodeId != InvalidNode and parser.nodes[decodeId].kind == .Array and parser.nodes[decodeId].values.count >= cast(u64) count * 2
    {
        for i in count
        {
            lowest[i]  = cast(f32) parser.number(parser.nodes[decodeId].values[i * 2])
            highest[i] = cast(f32) parser.number(parser.nodes[decodeId].values[i * 2 + 1])
        }
    }

    result.rgb.resize(pixelCount * 3)
    var components: [8] f32
    var target:     [3] u8
    for y in cast(u64) height
    {
        let rowBase = y * rowBytes
        for x in cast(u64) width
        {
            for i in count
            {
                let raw = sampleAt(bytes.toSlice(), rowBase, x * cast(u64) space.components + i, depth)
                components[i] = lowest[i] + cast(f32) raw * (highest[i] - lowest[i]) / maxValue
            }

            let pixel = (y * cast(u64) width + x) * 3
            if space.kind != .Indexed
            {
                writeColor(&space, space.kind, components, target)
                result.rgb[pixel + 0] = target[0]
                result.rgb[pixel + 1] = target[1]
                result.rgb[pixel + 2] = target[2]
                continue
            }

            let index     = cast(u32) Math.clamp(cast(s32) Math.round(components[0]), 0, cast(s32) space.hival)
            let baseCount = Math.min(space.baseComponents, 8'u32)
            let entry     = cast(u64) index * cast(u64) space.baseComponents
            var base: [8] f32
            for i in baseCount do
                base[i] = cast(f32) space.palette[entry + i] / 255.0

            // A palette entry is always eight bits wide, so a Lab base needs its own ranges
            // restored before the entry becomes a color.
            if space.baseKind == .Lab and baseCount >= 3
            {
                base[0] *= 100.0
                base[1] = space.range[0] + base[1] * (space.range[1] - space.range[0])
                base[2] = space.range[2] + base[2] * (space.range[3] - space.range[2])
            }

            var palette = space
            palette.components = space.baseComponents
            writeColor(&palette, space.baseKind, base, target)
            result.rgb[pixel + 0] = target[0]
            result.rgb[pixel + 1] = target[1]
            result.rgb[pixel + 2] = target[2]
        }
    }

    try applyColorKeyMask(parser, nodeId, &result, bytes.toSlice(), space, depth, rowBytes)
    return result
}

// Applies `/Mask` in its color-key form, where sample ranges select transparent pixels.
private func applyColorKeyMask(parser: *PdfParser, nodeId: u32, plane: *SamplePlane, bytes: const [..] u8, space: ImageSpace, depth: u32, rowBytes: u64) fail
{
    let maskId = parser.dict(nodeId, "Mask")
    if maskId == InvalidNode or parser.nodes[maskId].kind != .Array do
        return
    let ranges = parser.nodes[maskId].values
    if ranges.count < cast(u64) space.components * 2 do
        fail InvalidFormatError{"PDF color key mask does not cover every component"}

    plane.alpha.resize(cast(u64) plane.width * cast(u64) plane.height)
    for i in plane.alpha.count do
        plane.alpha[i] = 0xFF
    for y in cast(u64) plane.height
    {
        let rowBase = y * rowBytes
        for x in cast(u64) plane.width
        {
            var masked = true
            for i in space.components
            {
                let raw   = cast(s64) sampleAt(bytes, rowBase, x * cast(u64) space.components + i, depth)
                let lower = parser.integer(ranges[i * 2])
                let upper = parser.integer(ranges[i * 2 + 1])
                if raw < lower or raw > upper
                {
                    masked = false
                    break
                }
            }

            if masked do
                plane.alpha[y * cast(u64) plane.width + x] = 0
        }
    }
}

// Reads an image XObject as an 8-bit coverage plane, which is what a soft mask carries.
private func readMaskPlane(parser: *PdfParser, nodeId, resourcesId: u32, stencil: bool)->SamplePlane fail
{
    var result: retval
    if parser.imageCodec(nodeId) == "DCTDecode"
    {
        let raw     = try parser.decodeStream(nodeId, true)
        let decoded = try Image.decode(".jpg", raw.toSlice())
        result.width  = decoded.width
        result.height = decoded.height
        result.alpha.resize(cast(u64) decoded.width * cast(u64) decoded.height)
        for y in cast(u64) decoded.height
        {
            for x in cast(u64) decoded.width
            {
                let source = ((cast(u64) decoded.height - y - 1) * cast(u64) decoded.width + x) * decoded.bytesPerPixel
                result.alpha[y * cast(u64) decoded.width + x] = decoded.pixels[source]
            }
        }

        return result
    }

    let width  = parser.integer(parser.dict(nodeId, "Width"))
    let height = parser.integer(parser.dict(nodeId, "Height"))
    if width <= 0 or height <= 0 or width > Swag.S32.Max or height > Swag.S32.Max do
        fail InvalidFormatError{"PDF image mask has invalid dimensions"}
    let bits = stencil ? 1's64 : parser.integer(parser.dict(nodeId, "BitsPerComponent"), 8)
    if bits != 1 and bits != 2 and bits != 4 and bits != 8 and bits != 16 do
        fail UnsupportedFormatError{"PDF image mask bit depth is not supported"}

    let depth    = cast(u32) bits
    let bytes    = try parser.decodeStream(nodeId)
    let rowBytes = (cast(u64) depth * cast(u64) width + 7) / 8
    if bytes.count < rowBytes * cast(u64) height do
        fail InvalidFormatError{"PDF image mask stream is truncated"}

    // A stencil mask paints where the sample is zero, so its default decode inverts the
    // coverage a soft mask would produce.
    var lowest   = stencil ? 1.0'f32 : 0.0'f32
    var highest  = stencil ? 0.0'f32 : 1.0'f32
    let decodeId = parser.dict(nodeId, "Decode")
    if decodeId != InvalidNode and parser.nodes[decodeId].kind == .Array and parser.nodes[decodeId].values.count >= 2
    {
        let first  = cast(f32) parser.number(parser.nodes[decodeId].values[0])
        let second = cast(f32) parser.number(parser.nodes[decodeId].values[1])
        lowest  = stencil ? 1.0 - first : first
        highest = stencil ? 1.0 - second : second
    }

    let maxValue = cast(f32) ((1'u64 << depth) - 1)
    result.width  = cast(s32) width
    result.height = cast(s32) height
    result.alpha.resize(cast(u64) width * cast(u64) height)
    for y in cast(u64) height
    {
        let rowBase = y * rowBytes
        for x in cast(u64) width
        {
            let raw = sampleAt(bytes.toSlice(), rowBase, x, depth)
            result.alpha[y * cast(u64) width + x] = componentByte(lowest + cast(f32) raw * (highest - lowest) / maxValue)
        }
    }

    return result
}

// Samples a coverage plane at the resolution of the image it masks.
private func sampleAlpha(mask: const *SamplePlane, x, y: u64, width, height: u64)->u8
{
    let sourceX = Math.min(cast(u64) mask.width - 1, x * cast(u64) mask.width / width)
    let sourceY = Math.min(cast(u64) mask.height - 1, y * cast(u64) mask.height / height)
    return mask.alpha[sourceY * cast(u64) mask.width + sourceX]
}

// Turns a top-down plane into a Pixel image, whose rows run bottom-up.
private func planeToImage(plane: const *SamplePlane, fill: #null const *Color)->Image
{
    let width  = cast(u64) plane.width
    let height = cast(u64) plane.height
    if !plane.alpha.count and !fill
    {
        var opaque: Array'u8
        opaque.reserve(width * height * 3)
        var row = height
        while row
        {
            row -= 1
            opaque.add(plane.rgb.toSlice()[row * width * 3 until (row + 1) * width * 3])
        }

        return Image.create(plane.width, plane.height, .RGB8, opaque.toSlice())
    }

    var pixels: Array'u8
    pixels.resize(width * height * 4)
    for y in height
    {
        let targetRow = (height - y - 1) * width
        for x in width
        {
            let target = (targetRow + x) * 4
            if fill
            {
                pixels[target + 0] = fill.r
                pixels[target + 1] = fill.g
                pixels[target + 2] = fill.b
            }
            else
            {
                let source = (y * width + x) * 3
                pixels[target + 0] = plane.rgb[source + 0]
                pixels[target + 1] = plane.rgb[source + 1]
                pixels[target + 2] = plane.rgb[source + 2]
            }

            pixels[target + 3] = plane.alpha[y * width + x]
        }
    }

    return Image.create(plane.width, plane.height, .RGBA8, pixels.toSlice())
}

// Decodes one image XObject or inline image into an owned Pixel image.
//
// `fillColor` paints a stencil mask, whose samples carry coverage rather than color.
internal func decodeImage(parser: *PdfParser, nodeId, resourcesId: u32, fillColor: Color)->Image fail
{
    if parser.boolean(parser.dict(nodeId, "ImageMask"))
    {
        let stencil = try readMaskPlane(parser, nodeId, resourcesId, true)
        return planeToImage(&stencil, &fillColor)
    }

    let codec = parser.imageCodec(nodeId)
    var plane: SamplePlane
    if !codec.isEmpty()
    {
        if codec != "DCTDecode" and codec != "DCT" do
            fail UnsupportedFormatError{"PDF image codec is not supported"}
        let raw     = try parser.decodeStream(nodeId, true)
        let decoded = try Image.decode(".jpg", raw.toSlice())
        plane.width  = decoded.width
        plane.height = decoded.height
        plane.rgb.resize(cast(u64) decoded.width * cast(u64) decoded.height * 3)

        // Pixel hands back a bottom-up image; the plane is top-down until it is flipped back.
        let swapRedBlue = decoded.pixelFormat == .BGR8 or decoded.pixelFormat == .BGRA8
        for y in cast(u64) decoded.height
        {
            for x in cast(u64) decoded.width
            {
                let source = ((cast(u64) decoded.height - y - 1) * cast(u64) decoded.width + x) * decoded.bytesPerPixel
                let target = (y * cast(u64) decoded.width + x) * 3
                plane.rgb[target + 0] = decoded.pixels[source + (swapRedBlue ? 2 : 0)]
                plane.rgb[target + 1] = decoded.pixels[source + 1]
                plane.rgb[target + 2] = decoded.pixels[source + (swapRedBlue ? 0 : 2)]
            }
        }
    }
    else do
        plane = try readSamplePlane(parser, nodeId, resourcesId)

    // A soft mask, or a stencil named through /Mask, supplies the alpha channel.
    var maskId  = parser.dict(nodeId, "SMask")
    var stencil = false
    if maskId == InvalidNode
    {
        let explicitMask = parser.dict(nodeId, "Mask")
        if explicitMask != InvalidNode and parser.nodes[explicitMask].kind == .Dictionary
        {
            maskId  = explicitMask
            stencil = true
        }
    }

    if maskId != InvalidNode
    {
        let mask = try readMaskPlane(parser, maskId, resourcesId, stencil)
        if mask.alpha.count
        {
            let width  = cast(u64) plane.width
            let height = cast(u64) plane.height
            plane.alpha.resize(width * height)
            for y in height
            {
                for x in width do
                    plane.alpha[y * width + x] = sampleAlpha(&mask, x, y, width, height)
            }
        }
    }

    return planeToImage(&plane, null)
}
