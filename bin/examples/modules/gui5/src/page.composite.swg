using Core, Gui, Pixel

func createCompositePage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "ColorPickerCtrl with alpha",
                             "Full control with 2D color modes, hue/alpha bars, ARGB edits and screen picker button.",
                             layout.left)
    scope
    {
        let picker = ColorPickerCtrl.create(left, {24, 84}, .All)
        picker.setFrameForm(.Round)
        picker.setColor(g_Color)
        picker.sigColorChanged += func(picker) { setSelectedColor(picker.color(), "ColorPickerCtrl alpha") }
        discard createQuickPalette(left, {380, 124, layout.left.width - 404, 136}, "Shared presets")
    }

    let right = createPanel(parent,
                            "Opaque ColorPickerCtrl",
                            "The same composite without alpha, showing RGB-only edit behavior and mode buttons.",
                            layout.right)
    scope
    {
        var opaque = g_Color
        opaque.a = 255
        let picker = ColorPickerCtrl.create(right, {24, 84}, .All & ~.AllowAlpha)
        picker.setFrameForm(.Round)
        picker.setColor(opaque)
        picker.sigColorChanged += func(picker) { setSelectedColor(picker.color(), "ColorPickerCtrl opaque") }
        discard createQuickPalette(right, {380, 124, layout.right.width - 404, 136}, "Opaque presets")
    }

    let bottom = createPanel(parent,
                             "Shared selection",
                             "All controls in this example write to one selected color so each page can be inspected independently.",
                             layout.bottom)
    discard createPreview(bottom, Math.Rectangle{18, 86, layout.bottom.width - 36, layout.bottom.height - 104}, &onLivePreviewEvent)
}
