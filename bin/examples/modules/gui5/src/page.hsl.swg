using Core, Gui, Pixel

func createHslModesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent, "HSL planes", "Two-dimensional HSL pickers cover the principal hue, saturation and lightness relationships.", layout.left)
    {
        discard createModePicker(left, "Saturation / lightness", {24, 120, 250, 210}, .SaturationLightness)
        discard createModePicker(left, "Hue / saturation", {314, 120, 250, 210}, .HueSaturation)
    }

    let right = createPanel(parent, "Hue / lightness", "A second hue plane plus vertical bars show cursor and gradient variants.", layout.right)
    {
        discard createModePicker(right, "Hue / lightness", {24, 120, 250, 210}, .HueLightness)
        discard createModePicker(right, "Hue", {300, 120, 28, 210}, .HueVertical)
        discard createModePicker(right, "Light", {364, 120, 28, 210}, .LightnessVertical)
        discard createModePicker(right, "Sat", {428, 120, 28, 210}, .SaturationVertical)
        discard createModePicker(right, "Alpha", {492, 120, 28, 210}, .AlphaVertical)
    }

    let bottom = createPanel(parent, "HSL and alpha bars", "Horizontal bars are useful in compact toolbars and property popups.", layout.bottom)
    {
        discard createModePicker(bottom, "Hue", {24, 120, 260, 24}, .HueHorizontal)
        discard createModePicker(bottom, "Lightness", {330, 120, 260, 24}, .LightnessHorizontal)
        discard createModePicker(bottom, "Saturation", {636, 120, 260, 24}, .SaturationHorizontal)
        discard createModePicker(bottom, "Alpha", {942, 120, 260, 24}, .AlphaHorizontal)
        discard createQuickPalette(bottom, {24, 204, 520, 36}, "Fast presets")
    }
}
