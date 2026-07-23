using Core, Gui, Pixel

func createPalettesPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left = createPanel(parent, "Generated ramps", "PalettePicker can fill itself from hue, luminance and saturation helpers.", layout.left)
    {
        discard createPaletteRamp(left, "Hue families", {24, 118, 360, 68}, 0, g_Color)
        discard createPaletteRamp(left, "Luminance from selected", {24, 226, 360, 68}, 1, g_Color)
        discard createPaletteRamp(left, "Saturation from selected", {24, 334, 360, 68}, 2, g_Color)
    }

    let right = createPanel(parent, "Designed palettes", "Named sets and accent groups are regular palette entries with the same selection signal.", layout.right)
    {
        let warm = PalettePicker.create(right, {24, 118, 360, 68})
        warm.boxSize   = 30
        warm.boxMargin = 6
        warm.addColor(Argb.Crimson)
        warm.addColor(Argb.Tomato)
        warm.addColor(Argb.Coral)
        warm.addColor(Argb.Orange)
        warm.addColor(Argb.Goldenrod)
        warm.addColor(Argb.Gold)
        warm.addColor(Argb.Sienna)
        warm.addColor(Argb.Firebrick)
        warm.sigChanged += func(palette) { selectPaletteColor(palette, "Warm palette") }
        createCaption(right, "Warm set", 24, 90, 240)

        let cool = PalettePicker.create(right, {24, 226, 360, 68})
        cool.boxSize   = 30
        cool.boxMargin = 6
        cool.addColor(Argb.CornflowerBlue)
        cool.addColor(Argb.DeepSkyBlue)
        cool.addColor(Argb.Turquoise)
        cool.addColor(Argb.MediumSeaGreen)
        cool.addColor(Argb.SeaGreen)
        cool.addColor(Argb.SlateBlue)
        cool.addColor(Argb.MediumPurple)
        cool.addColor(Argb.DarkSlateGray)
        cool.sigChanged += func(palette) { selectPaletteColor(palette, "Cool palette") }
        createCaption(right, "Cool set", 24, 198, 240)

        discard createPaletteRamp(right, "Alpha set", {24, 334, 360, 68}, 3, g_Color, false)
    }

    let bottom = createPanel(parent, "Palette preview", "Selected palette colors keep the current alpha unless the alpha palette is used.", layout.bottom)
    {
        discard createPreview(bottom, {18, 86, layout.bottom.width - 36, layout.bottom.height - 104}, &onDerivedPreviewEvent)
    }
}
