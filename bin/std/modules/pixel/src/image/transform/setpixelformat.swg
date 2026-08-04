using Core

impl Image
{
    mtd const doRGB8(dstImage: *Image)
    {
        let mec = cast #unconst (*Image) me

        switch #complete .pixelFormat
        {
        case .RGB8:
            break

        case .RGBA8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[0]
                pixDst[1] = pix[1]
                pixDst[2] = pix[2]
            }

        case .BGR8, .BGRA8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[2]
                pixDst[1] = pix[1]
                pixDst[2] = pix[0]
            }
        }
    }

    mtd const doRGBA8(dstImage: *Image)
    {
        let mec = cast #unconst (*Image) me

        switch #complete .pixelFormat
        {
        case .RGBA8:
            break

        case .BGRA8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[2]
                pixDst[1] = pix[1]
                pixDst[2] = pix[0]
                pixDst[3] = pix[3]
            }

        case .RGB8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[0]
                pixDst[1] = pix[1]
                pixDst[2] = pix[2]
                pixDst[3] = 255
            }

        case .BGR8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[2]
                pixDst[1] = pix[1]
                pixDst[2] = pix[0]
                pixDst[3] = 255
            }
        }
    }

    mtd const doBGR8(dstImage: *Image)
    {
        let mec = cast #unconst (*Image) me

        switch #complete .pixelFormat
        {
        case .BGR8:
            break

        case .BGRA8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[0]
                pixDst[1] = pix[1]
                pixDst[2] = pix[2]
            }

        case .RGB8, .RGBA8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[2]
                pixDst[1] = pix[1]
                pixDst[2] = pix[0]
            }
        }
    }

    mtd const doBGRA8(dstImage: *Image)
    {
        let mec = cast #unconst (*Image) me

        switch #complete .pixelFormat
        {
        case .BGRA8:
            break

        case .BGR8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[0]
                pixDst[1] = pix[1]
                pixDst[2] = pix[2]
                pixDst[3] = 255
            }

        case .RGB8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[2]
                pixDst[1] = pix[1]
                pixDst[2] = pix[0]
                pixDst[3] = 255
            }

        case .RGBA8:
            mec.visitPixels(dstImage)
            {
                let dstImage = cast(*Image) userData!
                let pixDst   = dstImage.pixels.buffer! + x * dstImage.bytesPerPixel + y * dstImage.rowStride
                pixDst[0] = pix[2]
                pixDst[1] = pix[1]
                pixDst[2] = pix[0]
                pixDst[3] = pix[3]
            }
        }
    }

    mtd const doChangePf(dstImage: *Image)
    {
        switch #complete dstImage.pixelFormat
        {
        case .RGB8:  .doRGB8(dstImage)
        case .RGBA8: .doRGBA8(dstImage)
        case .BGR8:  .doBGR8(dstImage)
        case .BGRA8: .doBGRA8(dstImage)
        }
    }

    // Change image pixel format
    public mtd convertTo(newPf: PixelFormat)
    {
        Debug.assert(.pixels.buffer != null)

        if newPf == .pixelFormat do
            return

        .allocWorkingBuffer(.width, .height, newPf)
        .doChangePf(.safeWorkingBuffer())
        .applyWorkingBuffer()
    }

    // Change image pixel format
    public mtd const convertedTo(newPf: PixelFormat)->Image
    {
        Debug.assert(.pixels.buffer != null)

        if newPf == .pixelFormat do
            return me

        var result: retval = create(.width, .height, newPf)
        .doChangePf(&result)
        return result
    }
}
