using Core, Gui, Pixel

func createHslModesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "HSL planes",
                             "Two-dimensional HSL pickers cover the principal hue, saturation and lightness relationships.",
                             layout.left)
    scope
    {
        const Margin = 24.0
        const Gap    = 20.0
        let planeWidth = (layout.left.width - 2 * Margin - Gap) * 0.5
        discard createModePicker(left, "Saturation / lightness", {Margin, 120, planeWidth, 210}, .SaturationLightness)
        discard createModePicker(left, "Hue / saturation", {Margin + planeWidth + Gap, 120, planeWidth, 210}, .HueSaturation)
    }

    let right = createPanel(parent,
                            "Hue / lightness",
                            "A second hue plane plus vertical bars show cursor and gradient variants.",
                            layout.right)
    scope
    {
        const Margin   = 24.0
        const BarPitch = 48.0
        let barX = layout.right.width - Margin - 4 * BarPitch
        discard createModePicker(right, "Hue / lightness", {Margin, 120, barX - 2 * Margin, 210}, .HueLightness)
        discard createModePicker(right, "Hue", {barX, 120, 28, 210}, .HueVertical)
        discard createModePicker(right, "Light", {barX + BarPitch, 120, 28, 210}, .LightnessVertical)
        discard createModePicker(right, "Sat", {barX + 2 * BarPitch, 120, 28, 210}, .SaturationVertical)
        discard createModePicker(right, "Alpha", {barX + 3 * BarPitch, 120, 28, 210}, .AlphaVertical)
    }

    let bottom = createPanel(parent,
                             "HSL and alpha bars",
                             "Horizontal bars are useful in compact toolbars and property popups.",
                             layout.bottom)
    scope
    {
        const Margin = 24.0
        const Gap    = 18.0
        let barWidth = (layout.bottom.width - 2 * Margin - 3 * Gap) / 4
        let pitch    = barWidth + Gap
        discard createModePicker(bottom, "Hue", {Margin, 100, barWidth, 24}, .HueHorizontal)
        discard createModePicker(bottom, "Lightness", {Margin + pitch, 100, barWidth, 24}, .LightnessHorizontal)
        discard createModePicker(bottom, "Saturation", {Margin + 2 * pitch, 100, barWidth, 24}, .SaturationHorizontal)
        discard createModePicker(bottom, "Alpha", {Margin + 3 * pitch, 100, barWidth, 24}, .AlphaHorizontal)
        discard createQuickPalette(bottom, {Margin, 173, 520, 36}, "Fast presets")
    }
}
