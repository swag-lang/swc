using Core, Gui, Pixel

func createCompositePage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "With alpha",
                             "The full control: 2D colour modes, hue and alpha bars, ARGB fields and the screen picker.",
                             layout.left)
    scope
    {
        let picker = ColorPickerCtrl.create(left, {24, 92}, .All)
        picker.setFrameForm(.Round)
        picker.setColor(g_Color)
        picker.sigColorChanged += func(picker) { setSelectedColor(picker.color(), "ColorPickerCtrl alpha") }
        discard createQuickPalette(left, {396, 124, 180, 200}, "Shared presets")
    }

    let right = createPanel(parent,
                            "Opaque",
                            "The same composite without alpha: RGB fields only.",
                            layout.right)
    scope
    {
        var opaque = g_Color
        opaque.a = 255
        let picker = ColorPickerCtrl.create(right, {24, 92}, .All & ~.AllowAlpha)
        picker.setFrameForm(.Round)
        picker.setColor(opaque)
        picker.sigColorChanged += func(picker) { setSelectedColor(picker.color(), "ColorPickerCtrl opaque") }
        discard createQuickPalette(right, {396, 124, 180, 200}, "Opaque presets")
    }

    let bottom = createPanel(parent,
                             "Shared selection",
                             "Every control of this example writes one selected colour, so each page can be inspected on its own.",
                             layout.bottom)
    discard createPreview(bottom, &onLivePreviewEvent)
}
