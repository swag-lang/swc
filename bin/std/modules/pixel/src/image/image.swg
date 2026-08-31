#global public

using Swag, Core, Core.Serialization

// Owns a two-dimensional, tightly packed pixel buffer.
//
// Pixels are stored row by row without padding in the format given by [[Pixel.PixelFormat]].
// Copying an image copies its owned byte array; temporary working storage is never shared.
//
// ## Example
//
// ```swag
// var image = Image.create(64, 64, .RGBA8)
// image.fill(Color.fromRgb(18, 24, 32))
// ```
#[Core.Serialization.Schema("pixel.image")]
struct Image
{
    public
    {
        #[Core.Serialization.Key("pixels")]
        pixels: Array'u8     // Owned, row-major pixel bytes.

        #[Core.Serialization.Key("metadata")]
        metadata: Array'ImageMetadata     // Format-specific metadata preserved by compatible codecs.

        // Geometry and encoding of the pixel buffer. They are established together by 'create' and
        // the decoders, and every one of them is derived from the others: writing one on its own
        // would describe a buffer that does not exist.
        //
        // Explicit serialization keys keep these persisted names independent from future source
        // renames.
        readonly
        {
            #[Core.Serialization.Key("byteCount")]
            byteCount: u64     // Total pixel-buffer size, in bytes.

            #[Core.Serialization.Key("width")]
            width: s32     // Image width, in pixels.

            #[Core.Serialization.Key("height")]
            height: s32     // Image height, in pixels.

            #[Core.Serialization.Key("rowStride")]
            rowStride: s32     // Byte stride of one tightly packed row.

            #[Core.Serialization.Key("pixelFormat")]
            pixelFormat: PixelFormat     // Encoding of each pixel.

            #[Core.Serialization.Key("alphaMode")]
            alphaMode: AlphaMode     // Relationship between stored RGB and alpha samples.

            #[Core.Serialization.Key("bitsPerPixel")]
            bitsPerPixel: u8     // Number of bits per pixel.

            #[Core.Serialization.Key("bytesPerPixel")]
            bytesPerPixel: u8     // Number of bytes per pixel.
        }
    }

    // Reusable scratch image owned by this image, allocated on demand by the transforms.
    #[Core.Serialization.NoSerialize]
    workingBuffer: #null *Image
}

// One logical pixel in the representation used between storage formats.
// Integer formats map their full range to zero through one; floating-point formats retain
// finite values outside that range so HDR conversions do not clip until an integer target asks.
internal struct PixelValue
{
    r: f32
    g: f32
    b: f32
    a: f32 = 1
}

#[Swag.Inline]
internal func colorPixelValue(color: Color)->PixelValue
{
    return {color.r / 255.0, color.g / 255.0, color.b / 255.0, color.a / 255.0}
}

internal func hslPixelValue(hue, saturation, lightness: f32)->PixelValue
{
    func hueComponent(m1, m2, hue: f32)->f32
    {
        var h = hue
        if h < 0 do
            h += 1
        if h > 1 do
            h -= 1
        if 6 * h < 1 do
            return m1 + (m2 - m1) * h * 6
        if 2 * h < 1 do
            return m2
        if 3 * h < 2 do
            return m1 + (m2 - m1) * ((2.0 / 3.0) - h) * 6
        return m1
    }

    let h = Math.saturate(hue)
    let s = Math.saturate(saturation)
    let l = Math.saturate(lightness)
    if s == 0 do
        return {l, l, l, 1}
    let m2 = l < 0.5 ? l * (1 + s) : (l + s) - l * s
    let m1 = 2 * l - m2
    return {hueComponent(m1, m2, h + 1.0 / 3.0), hueComponent(m1, m2, h), hueComponent(m1, m2, h - 1.0 / 3.0), 1}
}

#[Swag.Inline]
internal func normalizedToU8(value: f32)->u8
{
    if value != value do
        return 0
    return cast(u8) Math.round(Math.clamp(value, 0.0, 1.0) * 255.0)
}

#[Swag.Inline]
internal func normalizedToU16(value: f32)->u16
{
    if value != value do
        return 0
    return cast(u16) Math.round(Math.clamp(value, 0.0, 1.0) * 65535.0)
}

#[Swag.Inline]
internal func readPixelValue(source: const [*] u8, format: PixelFormat)->PixelValue
{
    var result: retval
    switch #complete format
    {
    case .Gray8:
        let value = cast(f32) source[0] / 255.0
        result = {value, value, value, 1}

    case .GrayAlpha8:
        let value = cast(f32) source[0] / 255.0
        result = {value, value, value, cast(f32) source[1] / 255.0}

    case .Gray16, .GrayAlpha16:
        let value = cast(f32) source[as u16] / 65535.0
        result = {value, value, value, format == .GrayAlpha16 ? cast(f32) (source + 2)[as u16] / 65535.0 : 1}

    case .GrayF16, .GrayAlphaF16:
        let value = halfToFloat(source[as u16])
        result = {value, value, value, format == .GrayAlphaF16 ? halfToFloat((source + 2)[as u16]) : 1}

    case .GrayF32, .GrayAlphaF32:
        let value = source[as f32]
        result = {value, value, value, format == .GrayAlphaF32 ? (source + 4)[as f32] : 1}

    case .BGR8:
        result = {cast(f32) source[2] / 255.0, cast(f32) source[1] / 255.0, cast(f32) source[0] / 255.0, 1}

    case .BGRA8:
        result = {cast(f32) source[2] / 255.0, cast(f32) source[1] / 255.0, cast(f32) source[0] / 255.0, cast(f32) source[3] / 255.0}

    case .RGB8:
        result = {cast(f32) source[0] / 255.0, cast(f32) source[1] / 255.0, cast(f32) source[2] / 255.0, 1}

    case .RGBA8:
        result = {cast(f32) source[0] / 255.0, cast(f32) source[1] / 255.0, cast(f32) source[2] / 255.0, cast(f32) source[3] / 255.0}

    case .RGB16:
        result = {cast(f32) source[as u16] / 65535.0, cast(f32) (source + 2)[as u16] / 65535.0, cast(f32) (source + 4)[as u16] / 65535.0, 1}

    case .RGBA16:
        result = {cast(f32) source[as u16] / 65535.0, cast(f32) (source + 2)[as u16] / 65535.0, cast(f32) (source + 4)[as u16] / 65535.0, cast(f32) (source + 6)[as u16] / 65535.0}

    case .RGBF16:
        result = {halfToFloat(source[as u16]), halfToFloat((source + 2)[as u16]), halfToFloat((source + 4)[as u16]), 1}

    case .RGBAF16:
        result = {halfToFloat(source[as u16]), halfToFloat((source + 2)[as u16]), halfToFloat((source + 4)[as u16]), halfToFloat((source + 6)[as u16])}

    case .RGBF32:
        result = {source[as f32], (source + 4)[as f32], (source + 8)[as f32], 1}

    case .RGBAF32:
        result = {source[as f32], (source + 4)[as f32], (source + 8)[as f32], (source + 12)[as f32]}

    case .Yuv420:
        Debug.assert(false, "a planar pixel cannot be read from packed storage")
    }

    return result
}

#[Swag.Inline]
internal func writePixelValue(destination: [*] u8, format: PixelFormat, value: PixelValue)
{
    switch #complete format
    {
    case .Gray8, .GrayAlpha8:
        destination[0] = normalizedToU8(value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722)
        if format == .GrayAlpha8 do
            destination[1] = normalizedToU8(value.a)

    case .Gray16, .GrayAlpha16:
        destination[as u16] = normalizedToU16(value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722)
        if format == .GrayAlpha16 do
            (destination + 2)[as u16] = normalizedToU16(value.a)

    case .GrayF16, .GrayAlphaF16:
        destination[as u16] = floatToHalf(value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722)
        if format == .GrayAlphaF16 do
            (destination + 2)[as u16] = floatToHalf(value.a)

    case .GrayF32, .GrayAlphaF32:
        destination[as f32] = value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
        if format == .GrayAlphaF32 do
            (destination + 4)[as f32] = value.a

    case .BGR8:
        destination[0] = normalizedToU8(value.b)
        destination[1] = normalizedToU8(value.g)
        destination[2] = normalizedToU8(value.r)

    case .BGRA8:
        destination[0] = normalizedToU8(value.b)
        destination[1] = normalizedToU8(value.g)
        destination[2] = normalizedToU8(value.r)
        destination[3] = normalizedToU8(value.a)

    case .RGB8, .RGBA8:
        destination[0] = normalizedToU8(value.r)
        destination[1] = normalizedToU8(value.g)
        destination[2] = normalizedToU8(value.b)
        if format == .RGBA8 do
            destination[3] = normalizedToU8(value.a)

    case .RGB16, .RGBA16:
        destination[as u16]       = normalizedToU16(value.r)
        (destination + 2)[as u16] = normalizedToU16(value.g)
        (destination + 4)[as u16] = normalizedToU16(value.b)
        if format == .RGBA16 do
            (destination + 6)[as u16] = normalizedToU16(value.a)

    case .RGBF16, .RGBAF16:
        destination[as u16]       = floatToHalf(value.r)
        (destination + 2)[as u16] = floatToHalf(value.g)
        (destination + 4)[as u16] = floatToHalf(value.b)
        if format == .RGBAF16 do
            (destination + 6)[as u16] = floatToHalf(value.a)

    case .RGBF32, .RGBAF32:
        destination[as f32]       = value.r
        (destination + 4)[as f32] = value.g
        (destination + 8)[as f32] = value.b
        if format == .RGBAF32 do
            (destination + 12)[as f32] = value.a

    case .Yuv420:
        Debug.assert(false, "a planar pixel cannot be written to packed storage")
    }
}

#[Swag.Inline]
internal func readLogicalPixelValue(source: const [*] u8, format: PixelFormat, alphaMode: AlphaMode)->PixelValue
{
    var result: retval = readPixelValue(source, format)
    if alphaMode == .Premultiplied
    {
        if result.a > 0
        {
            result.r /= result.a
            result.g /= result.a
            result.b /= result.a
        }
        else
        {
            result.r = 0
            result.g = 0
            result.b = 0
        }
    }

    return result
}

#[Swag.Inline]
internal func writeLogicalPixelValue(destination: [*] u8, format: PixelFormat, alphaMode: AlphaMode, value: PixelValue)
{
    var stored = value
    if alphaMode == .Premultiplied
    {
        stored.r *= stored.a
        stored.g *= stored.a
        stored.b *= stored.a
    }

    writePixelValue(destination, format, stored)
}

impl Image
{
    // Reports whether the image owns an allocated pixel buffer.
    #[Swag.Inline]
    mtd const isValid() => .pixels.buffer != null

    // Creates a tightly packed image with positive dimensions.
    //
    // When `buffer` is provided, its bytes are copied into the new image. Its length
    // must exactly match the byte count implied by the dimensions and format.
    //
    // ## Example
    //
    // ```swag
    // let pixels: [4] u8 = {255, 0, 0, 255}
    // let image = Image.create(1, 1, .RGBA8, pixels)
    // ```
    func create(width, height: s32, pixelFormat: PixelFormat, buffer: #null const [..] u8 = null, alphaMode = AlphaMode.Straight)->Image
    {
        Debug.assert(width > 0 and height > 0, "invalid dimensions")

        var result: retval
        result.init(width, height, pixelFormat, alphaMode)
        result.allocPixels()
        if buffer
        {
            Debug.assert(buffer.count == result.byteCount, "pixel buffer size does not match image geometry")
            Memory.copy(cast([*] u8) result.pixels.buffer!, buffer.buffer, buffer.count)
        }

        return result
    }

    // Releases temporary working storage when the image leaves scope.
    mtd opDrop()
    {
        Memory.delete'Image(.workingBuffer)
    }

    // Detaches temporary working storage after copying the image.
    mtd opPostCopy()
    {
        .workingBuffer = null
    }

    // Visits every pixel in storage order.
    //
    // The injected `pixel` value is the address of the current pixel and `index` is
    // its zero-based row-major ordinal. Set `back` to use reverse visitation where
    // supported by the macro invocation.
    #[Swag.Macro]
    func(ptr: bool) opVisit(me, stmt: #code(var pixel, var index: u64))
    {
        var scan = pixels.buffer
        for width * height
        {
            #inject(stmt, pixel = scan, index = Swag.index)

            scan += bytesPerPixel
        }
    }

    // Initializes image geometry without allocating pixels.
    //
    // This resets `pixels`, metadata, and temporary storage. Call [[Image.allocPixels]]
    // afterward, or supply storage through a higher-level creation operation.
    internal mtd init(width, height: s32, pixelFormat: PixelFormat, alphaMode = AlphaMode.Straight)
    {
        Debug.assert(width > 0 and height > 0, "invalid dimensions")
        let bitsPerPixel = pixelFormat.bitsPerPixel()
        Debug.assert(pixelFormat.isPacked(), "an image holds a packed pixel format")
        Debug.assert(pixelFormat.hasAlpha() or alphaMode == .Straight, "a format without alpha cannot be premultiplied")
        let bytesPerPixel = cast(u8) (bitsPerPixel >> 3)
        Debug.assert(width <= 0x7FFFFFFF's32 / cast(s32) bytesPerPixel, "image row is too large")

        .release()
        .width         = width
        .height        = height
        .pixelFormat   = pixelFormat
        .alphaMode     = alphaMode
        .bitsPerPixel  = bitsPerPixel
        .bytesPerPixel = bytesPerPixel
        .rowStride     = .width * .bytesPerPixel
        .byteCount     = cast(u64) .rowStride * cast(u64) .height
    }

    // Allocates the pixel buffer without initializing its bytes.
    internal mtd allocPixels()
    {
        Debug.assert(.byteCount != 0)

        // Do not use pixels.resize to avoid initializing all the pixels
        // Pixels are not defined after a call to 'allocPixels', as design
        .pixels.grow(.byteCount)
        .pixels.count = .byteCount
    }

    // Allocates reusable working storage with the current geometry and pixel format.
    internal mtd allocWorkingBuffer()
    {
        .allocWorkingBuffer(.width, .height, .pixelFormat, .alphaMode)
    }

    // Allocates reusable working storage with the requested geometry and format.
    //
    // An existing compatible buffer is retained; an incompatible one is released.
    internal mtd allocWorkingBuffer(newWidth, newHeight: s32, newPixelFormat: PixelFormat)
    {
        .allocWorkingBuffer(newWidth, newHeight, newPixelFormat, newPixelFormat.hasAlpha() ? .alphaMode : .Straight)
    }

    internal mtd allocWorkingBuffer(newWidth, newHeight: s32, newPixelFormat: PixelFormat, newAlphaMode: AlphaMode)
    {
        if .workingBuffer and
           newWidth == .workingBuffer.width and
           newHeight == .workingBuffer.height and
           newPixelFormat == .workingBuffer.pixelFormat and
           newAlphaMode == .workingBuffer.alphaMode
        {
            return
        }

        .freeWorkingBuffer()
        .workingBuffer   = Memory.new'Image()
        .workingBuffer[] = Image.create(newWidth, newHeight, newPixelFormat, alphaMode: newAlphaMode)
    }

    // Returns the allocated working image.
    //
    // The caller must have called an `allocWorkingBuffer` overload first.
    internal mtd safeWorkingBuffer()->*Image
    {
        return .workingBuffer!
    }

    // Releases the working image, if any.
    internal mtd freeWorkingBuffer()
    {
        Memory.delete(.workingBuffer)
        .workingBuffer = null
    }

    // Visits every complete 16-byte block of the pixel buffer in parallel.
    #[Swag.Macro]
    internal mtd visitVectorBytes(contextData: #null *void = null, stmt: #code(var block, data))
    {
        const VectorSize = #sizeof(Math.Simd.U8x16)
        let count = .byteCount - .byteCount % VectorSize
        Jobs.parallelVisit(Swag.makeSlice(cast([*] u8) .pixels.buffer!, count), VectorSize, contextData) #code(buffer, rawData)
        {
            #inject(stmt, block = cast([*] u8) buffer, data = rawData)
        }
    }

    // Swaps the current pixels and geometry with the working image.
    //
    // Working storage must already be allocated. Metadata remains attached to the
    // current image.
    internal mtd applyWorkingBuffer()
    {
        let wb = .workingBuffer!
        swap(&.pixelFormat, &wb.pixelFormat)
        swap(&.alphaMode, &wb.alphaMode)
        swap(&.pixels, &wb.pixels)
        swap(&.width, &wb.width)
        swap(&.height, &wb.height)
        swap(&.bitsPerPixel, &wb.bitsPerPixel)
        swap(&.bytesPerPixel, &wb.bytesPerPixel)
        swap(&.byteCount, &wb.byteCount)
        swap(&.rowStride, &wb.rowStride)
    }

    // Visits pixels in parallel using chunks separated by `stride` pixels.
    //
    // `stride` must be positive. Each injected invocation receives:
    //
    // | pix       | address of the pixel
    // | image     | the processed image
    // | index     | the pixel index
    // | x         | the pixel x coordinates
    // | y         | the pixel y coordinates
    // | userData  | as passed to the macro
    #[Swag.Macro]
    mtd visitPixels(pixelUserData: #null *void = null, stride: s32 = 1, stmt: #code(var pix, image, index: u64, x: s32, y: s32, userData))
    {
        Debug.assert(stride > 0)

        let self: const *Image = me
        var p = {image: self, userData: pixelUserData}
        Jobs.parallelVisit(Swag.makeSlice(cast([*] u8) self.pixels.buffer!, self.pixels.count), cast(u32) (.bytesPerPixel * stride), &p)
        {
            if !data do
                return
            let p        = cast(*#decltype(p)) (data)
            let pixPtr   = cast([*] u8) buffer
            let pixIndex = cast(u64) (pixPtr - cast([*] u8) p.image.pixels.buffer!) / p.image.bytesPerPixel

            #inject(stmt,
                    pix = pixPtr,
                    image = p.image,
                    index = pixIndex,
                    x = cast(s32) pixIndex % p.image.width,
                    y = cast(s32) pixIndex / p.image.width,
                    userData = p.userData)
        }
    }

    // Visits logical RGBA values in parallel and writes them back through the image's storage
    // format and alpha association. This is the common scalar fallback for filters whose packed
    // 8-bit specialization cannot represent a high-precision or grayscale image.
    #[Swag.Macro]
    internal mtd transformLogicalPixels(pixelUserData: #null *void = null,
                                        stmt: #code(var value: PixelValue, image: *Image, x: s32, y: s32, userData))
    {
        var context = {image: me, userData: pixelUserData}
        Jobs.parallelFor(cast(u32) .height, &context) #code(row, rawData)
        {
            let params = cast(*#decltype(context)) rawData!
            let image  = cast(*Image) params.image
            var pixel  = image.pixels.buffer! + cast(u64) row * image.rowStride
            for column in image.width
            {
                var logical = readLogicalPixelValue(pixel, image.pixelFormat, image.alphaMode)
                #inject(stmt, value = logical, image = image, x = column, y = cast(s32) row, userData = params.userData)
                writeLogicalPixelValue(pixel, image.pixelFormat, image.alphaMode, logical)
                pixel += image.bytesPerPixel
            }
        }
    }

    // Releases all owned image content and restores an empty value.
    mtd release()
    {
        Swag.drop(me, 1)
        Swag.init(me, 1)
    }

    // Sets every byte of the pixel buffer to zero.
    mtd clear()
    {
        Debug.assert(.isValid(), "image is invalid")
        let pixels = .pixels.buffer!
        Memory.clear(pixels, .byteCount)
    }

    // Copies one 24-bit or 32-bit pixel between non-null addresses.
    #[Swag.Inline]
    internal func(BPP: u8) copyPixelDirect(pixDst, pixSrc: [*] u8)
    {
        #static switch BPP
        {
        case 24:
            pixDst[as u16] = pixSrc[as u16]
            pixDst[2]      = pixSrc[2]

        case 32:
            pixDst[as u32] = pixSrc[as u32]

        default:
            #assert("invalid pixelCopy BPP")
        }
    }

    // Writes the low twelve bytes of a packed value without touching adjacent pixels.
    #[Swag.Inline]
    internal func storeLow12(destination: [*] u8, value: Math.Simd.U8x16)
    {
        (cast([*] u64) destination)[0]       = (cast #bit(Math.Simd.U64x2) value)[0]
        (cast([*] u32) (destination + 8))[0] = (cast #bit(Math.Simd.U32x4) value)[2]
    }

    // Applies one lookup table per color channel while preserving any alpha channel.
    internal mtd applyColorLuts(channel0, channel1, channel2: const [*] u8)
    {
        var context = {image: me, channel0: channel0, channel1: channel1, channel2: channel2}
        Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
        {
            let params = cast(*#decltype(context)) data!
            let image  = cast(*Image) params.image
            let pixels = image.pixels.buffer! + cast(u64) row * image.rowStride
            for x in image.width
            {
                let pixel = pixels + cast(u64) x * image.bytesPerPixel
                pixel[0] = params.channel0[pixel[0]]
                pixel[1] = params.channel1[pixel[1]]
                pixel[2] = params.channel2[pixel[2]]
            }
        }
    }

    // Writes RGBA components to `pixDst` using the compile-time pixel format.
    internal func(PF: PixelFormat) convertToRGBA8(pixDst: [*] u8, r, g, b, a: u8)
    {
        #static if PF == .BGR8
        {
            pixDst[0] = b
            pixDst[1] = g
            pixDst[2] = r
        }

        #static if PF == .BGRA8
        {
            pixDst[0] = b
            pixDst[1] = g
            pixDst[2] = r
            pixDst[3] = a
        }

        #static if PF == .RGB8
        {
            pixDst[0] = r
            pixDst[1] = g
            pixDst[2] = b
        }

        #static if PF == .RGBA8
        {
            pixDst[0] = r
            pixDst[1] = g
            pixDst[2] = b
            pixDst[3] = a
        }
    }

    // Reads one clamped pixel using the compile-time pixel format.
    #[Swag.Inline]
    internal mtd(PF: PixelFormat) const pixelColorDirect(pixX, pixY: s32)->Color
    {
        var result: retval
        let x = Math.clamp(pixX, 0, .width - 1)
        var y = Math.clamp(pixY, 0, .height - 1)
        y = .height - y - 1

        #static switch PF
        {
        case .RGBA8:
            let pix = .pixels.buffer! + (x * 4) + (y * .width * 4)
            result.r = pix[0]
            result.g = pix[1]
            result.b = pix[2]
            result.a = pix[3]

        case .RGB8:
            let pix = .pixels.buffer! + (x * 3) + (y * .width * 3)
            result.r = pix[0]
            result.g = pix[1]
            result.b = pix[2]
            result.a = 255

        case .BGRA8:
            let pix = .pixels.buffer! + (x * 4) + (y * .width * 4)
            result.b = pix[0]
            result.g = pix[1]
            result.r = pix[2]
            result.a = pix[3]

        case .BGR8:
            let pix = .pixels.buffer! + (x * 3) + (y * .width * 3)
            result.b = pix[0]
            result.g = pix[1]
            result.r = pix[2]
            result.a = 255
        }

        return result
    }

    // Returns the color at the given coordinate, clamped to the image bounds.
    mtd const pixelColor(pixX, pixY: s32)->Color
    {
        Debug.assert(.isValid(), "image is invalid")
        if .alphaMode == .Premultiplied
        {
            let x             = Math.clamp(pixX, 0, .width - 1)
            let y             = .height - Math.clamp(pixY, 0, .height - 1) - 1
            let source        = .pixels.buffer! + cast(u64) y * .rowStride + cast(u64) x * .bytesPerPixel
            let value         = readLogicalPixelValue(source, .pixelFormat, .alphaMode)
            var result: Color = undefined
            result.r = normalizedToU8(value.r)
            result.g = normalizedToU8(value.g)
            result.b = normalizedToU8(value.b)
            result.a = normalizedToU8(value.a)
            return result
        }

        switch #complete .pixelFormat
        {
        case .Gray8, .GrayAlpha8, .Gray16, .GrayAlpha16, .GrayF16, .GrayAlphaF16, .GrayF32, .GrayAlphaF32,
             .RGB16, .RGBA16, .RGBF16, .RGBAF16, .RGBF32, .RGBAF32:
            let x             = Math.clamp(pixX, 0, .width - 1)
            let y             = .height - Math.clamp(pixY, 0, .height - 1) - 1
            let source        = .pixels.buffer! + cast(u64) y * .rowStride + cast(u64) x * .bytesPerPixel
            let value         = readLogicalPixelValue(source, .pixelFormat, .alphaMode)
            var result: Color = undefined
            result.r = normalizedToU8(value.r)
            result.g = normalizedToU8(value.g)
            result.b = normalizedToU8(value.b)
            result.a = normalizedToU8(value.a)
            return result

        case .RGBA8:
            return .pixelColorDirect'RGBA8(pixX, pixY)

        case .RGB8:
            return .pixelColorDirect'RGB8(pixX, pixY)

        case .BGRA8:
            return .pixelColorDirect'BGRA8(pixX, pixY)

        case .BGR8:
            return .pixelColorDirect'BGR8(pixX, pixY)

        case .Yuv420:

            // An image never holds a planar format; 'create' refuses one.
            break
        }

        Debug.assert(false)
        return Color.fromArgb(0'u32)
    }

    // Returns the width divided by the height.
    mtd const aspectRatio()->f32
    {
        Debug.assert(.isValid(), "image is invalid")
        return cast(f32) .width / cast(f32) .height
    }

    // Reports whether the image has equal width and height.
    mtd const isSquare()->bool
    {
        if !.isValid() do
            return false
        return .width == .height
    }
}
