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
struct Image
{
    public
    {
        pixels: Array'u8     // Owned, row-major pixel bytes.

        #[Core.Serialization.Alias("metaDatas")]
        metadata: Array'ImageMetadata     // Format-specific metadata preserved by compatible codecs.

        // Geometry and encoding of the pixel buffer. They are established together by 'create' and
        // the decoders, and every one of them is derived from the others: writing one on its own
        // would describe a buffer that does not exist.
        //
        // The aliases are the names these fields carried before they were spelled out. A serialized
        // field is keyed by the CRC of its name, so a rename without an alias silently drops the
        // value: an image written by an older build would read back with no stride and no format,
        // and decode to noise.
        public readonly
        {
            #[Core.Serialization.Alias("size")]
            byteCount: u64     // Total pixel-buffer size, in bytes.

            width:  s32     // Image width, in pixels.
            height: s32     // Image height, in pixels.

            #[Core.Serialization.Alias("width8")]
            rowStride: s32     // Byte stride of one tightly packed row.

            #[Core.Serialization.Alias("pf")]
            pixelFormat: PixelFormat     // Encoding of each pixel.

            #[Core.Serialization.Alias("bpp")]
            bitsPerPixel: u8     // Number of bits per pixel.

            #[Core.Serialization.Alias("bpp8")]
            bytesPerPixel: u8     // Number of bytes per pixel.
        }

        // Reusable scratch image owned by this image, allocated on demand by the transforms.
        #[Core.Serialization.NoSerialize]
        internal
        workingBuffer: #null *Image
    }
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
    func create(width, height: s32, pixelFormat: PixelFormat, buffer: #null const [..] u8 = null)->Image
    {
        Debug.assert(width > 0 and height > 0, "invalid dimensions")

        var result: retval
        result.init(width, height, pixelFormat)
        result.allocPixels()
        if buffer
        {
            Debug.assert(@countof(buffer) == result.byteCount, "pixel buffer size does not match image geometry")
            Memory.copy(cast([*] u8) result.pixels.buffer!, @dataof(buffer), @countof(buffer))
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
            #inject(stmt, pixel = scan, index = @index)

            scan += bytesPerPixel
        }
    }

    // Initializes image geometry without allocating pixels.
    //
    // This resets `pixels`, metadata, and temporary storage. Call [[Image.allocPixels]]
    // afterward, or supply storage through a higher-level creation operation.
    internal mtd init(width, height: s32, pixelFormat: PixelFormat)
    {
        Debug.assert(width > 0 and height > 0, "invalid dimensions")
        let bitsPerPixel  = pixelFormat.bitsPerPixel()
        let bytesPerPixel = cast(u8) (bitsPerPixel >> 3)
        Debug.assert(width <= 0x7FFFFFFF's32 / cast(s32) bytesPerPixel, "image row is too large")

        .release()
        .width         = width
        .height        = height
        .pixelFormat   = pixelFormat
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
        .allocWorkingBuffer(.width, .height, .pixelFormat)
    }

    // Allocates reusable working storage with the requested geometry and format.
    //
    // An existing compatible buffer is retained; an incompatible one is released.
    internal mtd allocWorkingBuffer(newWidth, newHeight: s32, newPixelFormat: PixelFormat)
    {
        if .workingBuffer and
           newWidth == .workingBuffer.width and
           newHeight == .workingBuffer.height and
           newPixelFormat == .workingBuffer.pixelFormat
        {
            return
        }

        .freeWorkingBuffer()
        .workingBuffer   = Memory.new'Image()
        .workingBuffer[] = Image.create(newWidth, newHeight, newPixelFormat)
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

    // Swaps the current pixels and geometry with the working image.
    //
    // Working storage must already be allocated. Metadata remains attached to the
    // current image.
    internal mtd applyWorkingBuffer()
    {
        let wb = .workingBuffer!
        swap(&.pixelFormat, &wb.pixelFormat)
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
        Jobs.parallelVisit(@mkslice(cast([*] u8) self.pixels.buffer!, self.pixels.count), cast(u32) (.bytesPerPixel * stride), &p)
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

    // Releases all owned image content and restores an empty value.
    mtd release()
    {
        @drop(me, 1)
        @init(me, 1)
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
            (cast(*u16) pixDst)[] = (cast(*u16) pixSrc)[]
            pixDst[2]             = pixSrc[2]

        case 32:
            (cast(*u32) pixDst)[] = (cast(*u32) pixSrc)[]

        default:
            #assert("invalid pixelCopy BPP")
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
        switch #complete .pixelFormat
        {
        case .RGBA8: return .pixelColorDirect'RGBA8(pixX, pixY)
        case .RGB8:  return .pixelColorDirect'RGB8(pixX, pixY)
        case .BGRA8: return .pixelColorDirect'BGRA8(pixX, pixY)
        case .BGR8:  return .pixelColorDirect'BGR8(pixX, pixY)
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
