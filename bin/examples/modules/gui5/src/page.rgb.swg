using Core, Gui, Pixel

func createRgbModesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "RGB planes",
                             "ColorPicker can map two RGB channels at a time for direct component editing.",
                             layout.left)
    scope
    {
        const Margin = 24.0
        const Gap    = 16.0
        let planeWidth = (layout.left.width - 2 * Margin - 2 * Gap) / 3
        let pitch      = planeWidth + Gap
        discard createModePicker(left, "Red / green", {Margin, 122, planeWidth, planeWidth}, .RedGreen)
        discard createModePicker(left, "Red / blue", {Margin + pitch, 122, planeWidth, planeWidth}, .RedBlue)
        discard createModePicker(left, "Green / blue", {Margin + 2 * pitch, 122, planeWidth, planeWidth}, .GreenBlue)
    }

    let right = createPanel(parent,
                            "Vertical channel bars",
                            "Standalone red, green and blue pickers are available in vertical orientation.",
                            layout.right)
    scope
    {
        let pitch = (layout.right.width - 48) / 4
        let barX  = 24 + (pitch - 32) * 0.5
        discard createModePicker(right, "Red", {barX, 122, 32, 210}, .RedVertical)
        discard createModePicker(right, "Green", {barX + pitch, 122, 32, 210}, .GreenVertical)
        discard createModePicker(right, "Blue", {barX + 2 * pitch, 122, 32, 210}, .BlueVertical)
        discard createModePicker(right, "Alpha", {barX + 3 * pitch, 122, 32, 210}, .AlphaVertical)
    }

    let bottom = createPanel(parent,
                             "Horizontal channel bars",
                             "The same channel controls in a wide form with a derived-color palette underneath.",
                             layout.bottom)
    scope
    {
        const Margin = 24.0
        const Gap    = 18.0
        let barWidth = (layout.bottom.width - 2 * Margin - 3 * Gap) / 4
        let pitch    = barWidth + Gap
        discard createModePicker(bottom, "Red", {Margin, 100, barWidth, 24}, .RedHorizontal)
        discard createModePicker(bottom, "Green", {Margin + pitch, 100, barWidth, 24}, .GreenHorizontal)
        discard createModePicker(bottom, "Blue", {Margin + 2 * pitch, 100, barWidth, 24}, .BlueHorizontal)
        discard createModePicker(bottom, "Alpha", {Margin + 3 * pitch, 100, barWidth, 24}, .AlphaHorizontal)
        discard createQuickPalette(bottom, {Margin, 173, 520, 36}, "RGB presets")
    }
}
