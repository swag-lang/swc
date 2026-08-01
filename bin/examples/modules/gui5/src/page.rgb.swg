using Core, Gui, Pixel

func createRgbModesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent, "RGB planes", "ColorPicker can map two RGB channels at a time for direct component editing.", layout.left)
    {
        discard createModePicker(left, "Red / green", {24, 122, 176, 176}, .RedGreen)
        discard createModePicker(left, "Red / blue", {226, 122, 176, 176}, .RedBlue)
        discard createModePicker(left, "Green / blue", {428, 122, 176, 176}, .GreenBlue)
    }

    let right = createPanel(parent, "Vertical channel bars", "Standalone red, green and blue pickers are available in vertical orientation.", layout.right)
    {
        discard createModePicker(right, "Red", {120, 122, 32, 210}, .RedVertical)
        discard createModePicker(right, "Green", {250, 122, 32, 210}, .GreenVertical)
        discard createModePicker(right, "Blue", {380, 122, 32, 210}, .BlueVertical)
        discard createModePicker(right, "Alpha", {510, 122, 32, 210}, .AlphaVertical)
    }

    let bottom = createPanel(parent, "Horizontal channel bars", "The same channel controls in a wide form with a derived-color palette underneath.", layout.bottom)
    {
        discard createModePicker(bottom, "Red", {24, 118, 270, 24}, .RedHorizontal)
        discard createModePicker(bottom, "Green", {330, 118, 270, 24}, .GreenHorizontal)
        discard createModePicker(bottom, "Blue", {636, 118, 270, 24}, .BlueHorizontal)
        discard createModePicker(bottom, "Alpha", {942, 118, 270, 24}, .AlphaHorizontal)
        discard createQuickPalette(bottom, {24, 202, 520, 36}, "RGB presets")
    }
}
