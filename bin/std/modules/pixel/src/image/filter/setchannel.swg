using Core

public impl Image
{
    // Bit mask selecting destination channels for [[Image.setChannel]].
    #[Swag.EnumFlags]
    enum ChannelMode
    {
        Red                           // Red channel.
        Green                         // Green channel.
        Blue                          // Blue channel.
        Alpha                         // Alpha channel.
        RGB  = Red | Green | Blue     // All color channels.
        RGBA = RGB | Alpha            // All color and alpha channels.
    }

    // Selects the value copied into channels by [[Image.setChannel]].
    enum ChannelValueMode
    {
        Color       // Use the explicit `color` byte.
        MinRGB      // Use the smallest color channel of the current pixel.
        MaxRGB      // Use the largest color channel of the current pixel.
        MeanRGB     // Use the arithmetic mean of the current color channels.
        Alpha       // Use the current alpha channel.
    }

    // Change the alpha channel
    mtd setAlpha(value: u8 = 0)
    {
        if .pixelFormat != .BGRA8 do
            return

        var alphaByte = value
        .visitVectorBytes(&alphaByte) #code(block, data)
        {
            let alphaValue = cast(*u8) data!
            let alphaWord  = cast(u32) alphaValue[] << 24
            let pixels     = Math.Simd.load(cast([*] u32) block)
            Math.Simd.store(cast([*] u32) block, (pixels & Math.Simd.splat(0x00FF_FFFF'u32)) | Math.Simd.splat(alphaWord))
        }

        let alphaWord = cast(u32) value << 24
        let pixels    = cast([*] u32) .pixels.buffer!
        let count     = .byteCount / 4
        var offset    = (.byteCount - .byteCount % 16) / 4
        while offset < count
        {
            pixels[offset] = (pixels[offset] & 0x00FF_FFFF) | alphaWord
            offset         += 1
        }
    }

    // Change specified color channels
    mtd setChannel(mode: ChannelMode, value: ChannelValueMode, color: u8 = 0)
    {
        if .pixelFormat != .BGR8 and .pixelFormat != .BGRA8 do
            return

        // Remove alpha change if it does not exists
        var rmode = mode
        if .pixelFormat == .BGR8
        {
            rmode &= ~.Alpha
            if rmode == 0 or value == .Alpha do
                return
        }

        if value == .Color and .bytesPerPixel == 4
        {
            var mask = 0'u32
            if rmode & .Blue do
                mask |= 0x0000_00FF
            if rmode & .Green do
                mask |= 0x0000_FF00
            if rmode & .Red do
                mask |= 0x00FF_0000
            if rmode & .Alpha do
                mask |= 0xFF00_0000

            var context = {mask: mask, color: color}
            .visitVectorBytes(&context) #code(block, data)
            {
                let params      = cast(*#decltype(context)) data!
                let channelMask = Math.Simd.splat(params.mask)
                let replacement = cast #bit(Math.Simd.U32x4) Math.Simd.splat(params.color)
                let pixels      = Math.Simd.load(cast([*] u32) block)
                Math.Simd.store(cast([*] u32) block, (pixels & ~channelMask) | (replacement & channelMask))
            }

            let pixels = cast([*] u32) .pixels.buffer!
            let count  = .byteCount / 4
            let word   = cast(u32) color * 0x0101_0101
            var offset = (.byteCount - .byteCount % 16) / 4
            while offset < count
            {
                pixels[offset] = (pixels[offset] & ~mask) | (word & mask)
                offset         += 1
            }

            return
        }

        var context = {image: me, rmode: rmode, value: value, color: color}
        Jobs.parallelFor(cast(u32) .height, &context) #code(row, data)
        {
            let params = cast(*#decltype(context)) data!
            let image  = cast(*Image) params.image
            let pixels = image.pixels.buffer! + cast(u64) row * image.rowStride
            for x in image.width
            {
                let pix  = pixels + cast(u64) x * image.bytesPerPixel
                let mode = params.rmode

                var channelValue: u8 = undefined
                switch #complete params.value
                {
                case .Color:   channelValue = params.color
                case .MinRGB:  channelValue = Math.min(pix[0], pix[1], pix[2])
                case .MaxRGB:  channelValue = Math.max(pix[0], pix[1], pix[2])
                case .MeanRGB: channelValue = cast(u8) ((pix[0] + #prom pix[1] + #prom pix[2]) / 3)
                case .Alpha:   channelValue = pix[3]
                }

                if mode & .Blue do
                    pix[0] = channelValue
                if mode & .Green do
                    pix[1] = channelValue
                if mode & .Red do
                    pix[2] = channelValue
                if mode & .Alpha do
                    pix[3] = channelValue
            }
        }
    }
}
