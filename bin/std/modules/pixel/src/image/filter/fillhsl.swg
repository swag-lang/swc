using Core

public impl Image
{
    // Selects the HSL or RGB gradient written by [[Image.fillHsl]].
    public enum FillHslType
    {
        HueVert                 // Hue varies from top to bottom.
        HueHorz                 // Hue varies from left to right.
        SaturationVert          // Saturation varies vertically at the supplied hue.
        SaturationHorz          // Saturation varies horizontally at the supplied hue.
        LightnessVert           // Lightness varies vertically at the supplied hue and saturation.
        LightnessHorz           // Lightness varies horizontally at the supplied hue and saturation.
        HueSaturation           // Hue and saturation span the two image axes.
        HueLightness            // Hue and lightness span the two image axes.
        SaturationLightness     // Saturation and lightness span the two image axes.
        GreenBlue               // Green and blue span the two image axes; red comes from `color`.
        RedBlue                 // Red and blue span the two image axes; green comes from `color`.
        RedGreen                // Red and green span the two image axes; blue comes from `color`.
    }

    // Replaces the image with a color-selection gradient.
    //
    // `color` supplies channels held constant by the selected gradient. The operation
    // supports 8-bit RGB/BGR images with or without alpha; unsupported formats are
    // left unchanged. Existing alpha is replaced with full opacity.
    mtd fillHsl(fillType: FillHslType, color: Color = Color.fromArgb(Argb.White))
    {
        // unsupported pixel format
        if .pixelFormat.channels() < 3 or .pixelFormat.bitDepth() != 8 do
            return

        let hsl    = color.toHsl()
        var swapRB = .pixelFormat == .RGB8 or .pixelFormat == .RGBA8

        switch #complete fillType
        {
        case .HueVert:
            .visitPixels(&swapRB)
            {
                let swapRB  = userData![as bool]
                let factor0 = y / cast(f32) image.height
                let col     = Color.fromHsl(factor0, 1, 0.5)
                if swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .HueHorz:
            var pix = .pixels.buffer!
            for x in .width
            {
                let factor0 = x / cast(f32) .width
                let col     = Color.fromHsl(factor0, 1, 0.5)
                if swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if .pixelFormat.hasAlpha() do
                    pix[3] = 255
                pix += .bytesPerPixel
            }

            .visitPixels(stride: .width)
            {
                Memory.copy(pix, cast([*] u8) image.pixels.buffer!, cast(u64) image.width * image.bytesPerPixel)
            }

        case .SaturationVert:
            var pms = {hsl: hsl, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let swapRB  = params.swapRB
                let factor0 = y / cast(f32) image.height
                let col     = Color.fromHsl(params.hsl.h, factor0, 0.5)
                if swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .SaturationHorz:
            var pix = .pixels.buffer!
            for x in .width
            {
                let factor0 = x / cast(f32) .width
                let col     = Color.fromHsl(hsl.h, factor0, 0.5)
                if swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if .pixelFormat.hasAlpha() do
                    pix[3] = 255
                pix += .bytesPerPixel
            }

            .visitPixels(stride: .width)
            {
                Memory.copy(pix, cast([*] u8) image.pixels.buffer!, cast(u64) image.width * image.bytesPerPixel)
            }

        case .LightnessVert:
            var pms = {hsl: hsl, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let swapRB  = params.swapRB
                let factor0 = y / cast(f32) image.height
                let col     = Color.fromHsl(params.hsl.h, 1, factor0)
                if swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .LightnessHorz:
            var pix = .pixels.buffer!
            for x in .width
            {
                let factor0 = x / cast(f32) .width
                let col     = Color.fromHsl(hsl.h, hsl.s, factor0)
                if swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if .pixelFormat.hasAlpha() do
                    pix[3] = 255
                pix += .bytesPerPixel
            }

            .visitPixels(stride: .width)
            {
                Memory.copy(pix, cast([*] u8) image.pixels.buffer!, cast(u64) image.width * image.bytesPerPixel)
            }

        case .HueSaturation:
            var pms = {hsl: hsl, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let factor0 = x / cast(f32) image.width
                let factor1 = y / cast(f32) image.height
                let col     = Color.fromHsl(factor0, factor1, 0.5)
                if params.swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .HueLightness:
            var pms = {hsl: hsl, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let factor0 = x / cast(f32) image.width
                let factor1 = y / cast(f32) image.height
                let col     = Color.fromHsl(factor0, 1, factor1)
                if params.swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .SaturationLightness:
            var pms = {hsl: hsl, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let factor0 = x / cast(f32) image.width
                let factor1 = y / cast(f32) image.height
                var l       = 0.5 + ((1 - factor0) * 0.5)
                l = Math.lerp(0, l, factor1)
                let col = Color.fromHsl(params.hsl.h, factor0, l)
                if params.swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .GreenBlue:
            var pms = {fixedRed: color.r / 255.0, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let factor0 = x / cast(f32) image.width
                let factor1 = 1 - (y / cast(f32) image.height)
                let col     = Color.fromRgbF32(params.fixedRed, factor0, factor1)
                if params.swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .RedBlue:
            var pms = {fixedGreen: color.g / 255.0, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let factor0 = x / cast(f32) image.width
                let factor1 = 1 - (y / cast(f32) image.height)
                let col     = Color.fromRgbF32(factor0, params.fixedGreen, factor1)
                if params.swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }

        case .RedGreen:
            var pms = {fixedBlue: color.b / 255.0, swapRB: swapRB}
            .visitPixels(&pms)
            {
                let params  = userData![as #decltype(pms)]
                let factor0 = x / cast(f32) image.width
                let factor1 = 1 - (y / cast(f32) image.height)
                let col     = Color.fromRgbF32(factor0, factor1, params.fixedBlue)
                if params.swapRB
                {
                    pix[0] = col.r
                    pix[1] = col.g
                    pix[2] = col.b
                }
                else
                {
                    pix[0] = col.b
                    pix[1] = col.g
                    pix[2] = col.r
                }

                if image.pixelFormat.hasAlpha() do
                    pix[3] = 255
            }
        }
    }
}
