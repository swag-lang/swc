using Core, Pixel

struct BlendModeSample
{
    label: string
    mode:  BlendingMode
}

const ContrastBlendModes = [
    BlendModeSample{"Multiply", .Multiply},
    BlendModeSample{"Screen", .Screen},
    BlendModeSample{"Overlay", .Overlay},
    BlendModeSample{"Hard light", .HardLight},
    BlendModeSample{"Soft light", .SoftLight},
    BlendModeSample{"Color dodge", .ColorDodge},
    BlendModeSample{"Color burn", .ColorBurn},
    BlendModeSample{"Exclusion", .Exclusion}]

const ComponentBlendModes = [
    BlendModeSample{"Darken", .Darken},
    BlendModeSample{"Lighten", .Lighten},
    BlendModeSample{"Difference", .Difference},
    BlendModeSample{"Hue", .Hue},
    BlendModeSample{"Saturation", .Saturation},
    BlendModeSample{"Color", .Color},
    BlendModeSample{"Luminosity", .Luminosity},
    BlendModeSample{"Alpha reference", .Alpha}]

func drawBlendModeSample(painter: *Pixel.Painter, rect: Math.Rectangle, sample: BlendModeSample)
{
    painter.fillRoundRect(rect, 16, 16, Argb.White)
    painter.drawRoundRect(rect, 16, 16, Color.fromArgb(42, Argb.SlateGray), 1)
    painter.drawString(rect.x + 14, rect.y + 11, sample.label, g_LabelFont!, Argb.DarkSlateBlue)

    let preview = insetRect(rect, 14, 42, 14, 14)

    // Strokes use framebuffer alpha as temporary overlap coverage. Rebuild each
    // preview as an alpha-bearing surface immediately before its artistic pass.
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.fillRoundRect(preview, 12, 12, Brush.createLinearGradient(preview.x, preview.y, preview.right(), preview.bottom(), Argb.RoyalBlue, Argb.Goldenrod))

    painter.setColorMaskColor()
    painter.setBlendingMode(sample.mode)
    painter.fillCircle(preview.x + preview.width * 0.62, preview.y + preview.height * 0.47, preview.height * 0.32, Color.fromArgb(210, Argb.DeepPink))
    painter.fillRoundRect(preview.x + preview.width * 0.16, preview.y + preview.height * 0.54, preview.width * 0.58, preview.height * 0.27, 14, 14, Color.fromArgb(176, Argb.MediumSeaGreen))
    painter.setBlendingMode(.Alpha)

    painter.drawRoundRect(preview, 12, 12, Color.fromArgb(56, Argb.MidnightBlue), 1)
}

func drawBlendModeGrid(painter: *Pixel.Painter, samples: const [..] BlendModeSample)
{
    const Gap    = 14.0
    const Left   = 28.0
    const Top    = 104.0
    const Width  = 924.0
    const Height = 560.0

    let cardWidth  = (Width - Gap * 3) / 4
    let cardHeight = (Height - Gap) * 0.5
    for sample, [idx] in samples
    {
        let column = cast(f32) (idx % 4)
        let row    = cast(f32) (idx / 4)
        let rect   = Math.Rectangle{Left + column * (cardWidth + Gap), Top + row * (cardHeight + Gap), cardWidth, cardHeight}
        drawBlendModeSample(painter, rect, sample)
    }
}

func drawContrastBlendModesPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel contrast blend modes", "Page 9 : the same translucent magenta and green sources cross an opaque blue-to-gold backdrop in every sample.")
    drawBlendModeGrid(painter, ContrastBlendModes[to])
}

func drawComponentBlendModesPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel component blend modes", "Page 10 : comparisons and non-separable hue, saturation, color and luminosity transfers, plus Alpha as a reference.")
    drawBlendModeGrid(painter, ComponentBlendModes[to])
}
