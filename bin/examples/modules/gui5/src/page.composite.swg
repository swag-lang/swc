using Core, Gui, Pixel

func createCompositePage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left = createPanel(parent, "ColorPickerCtrl with alpha", "Full control with 2D color modes, hue/alpha bars, ARGB edits and screen picker button.", layout.left)
    {
        let picker = ColorPickerCtrl.create(left, {24, 92}, .All)
        picker.setFrameForm(.Round)
        picker.setColor(g_Color)
        picker.sigChanged += func(picker)
        {
            setSelectedColor(picker.getColor(), "ColorPickerCtrl alpha")
        }
        discard createQuickPalette(left, {400, 124, 196, 200}, "Shared presets")
    }

    let right = createPanel(parent, "Opaque ColorPickerCtrl", "The same composite without alpha, showing RGB-only edit behavior and mode buttons.", layout.right)
    {
        var opaque = g_Color
        opaque.a = 255
        let picker = ColorPickerCtrl.create(right, {24, 92}, .All & ~.Alpha)
        picker.setFrameForm(.Round)
        picker.setColor(opaque)
        picker.sigChanged += func(picker)
        {
            setSelectedColor(picker.getColor(), "ColorPickerCtrl opaque")
        }
        discard createQuickPalette(right, {400, 124, 196, 200}, "Opaque presets")
    }

    let bottom = createPanel(parent, "Shared selection", "All controls in this example write to one selected color so each page can be inspected independently.", layout.bottom)
    discard createPreview(bottom, {18, 86, layout.bottom.width - 36, layout.bottom.height - 104}, &onLivePreviewEvent)
}
