using Core, Gui, Pixel

func createPushButtonPage(parent: *Wnd)
{
    let left = createPanel(parent, "Forms", "The same command rendered with the standard push button forms.", {0, 0, 500, 250})
    {
        var btn = PushButton.create(left, "Normal", {22, 92, 150})
        btn.icon = app.theme.getIcon24(ThemeIcons24.Play, 18)

        btn = PushButton.create(left, "Default", {190, 92, 150})
        btn.form = .Default
        btn.icon = app.theme.getIcon24(ThemeIcons24.Save, 18)

        btn = PushButton.create(left, "Flat", {22, 142, 150})
        btn.form = .Flat
        btn.icon = app.theme.getIcon24(ThemeIcons24.Search, 18)

        btn = PushButton.create(left, "Strong", {190, 142, 150})
        btn.form = .Strong
        btn.icon = app.theme.getIcon24(ThemeIcons24.Download, 18)
    }

    let right = createPanel(parent, "States", "Hot/pressed states are interactive; disabled and long text variants check clipping.", {528, 0, 496, 250})
    {
        let status = createText(right, "No button pressed yet.", {22, 190, 430, 28})

        var btn = PushButton.create(right, "Press me", {22, 92, 150})
        btn.sigPressed += func|status|(btn)
        {
            status.setText("Pressed: standard button")
        }

        btn = PushButton.create(right, "Disabled", {190, 92, 150})
        btn.disable()

        btn = PushButton.create(right, "Long label clipped cleanly", {22, 142, 210})
        btn.form = .Default
        btn.sigPressed += func|status|(btn)
        {
            status.setText("Pressed: long label button")
        }

        btn = PushButton.create(right, "Help cursor", {250, 142, 150})
        btn.cursor = Cursor.from(CursorShape.Help)
    }

    let bottom = createPanel(parent, "Style override", "A flat button with custom colors, used as a compact visual regression target.", {0, 276, 1024, 248})
    {
        let btn = PushButton.create(bottom, "Custom flat action", {22, 96, 220})
        btn.form = .Flat
        btn.icon = app.theme.getIcon24(ThemeIcons24.Filter, 18)
        btn.style.addStyleSheetColors("btnPushFlat_HotBk 0xFF2F8F5B")
        btn.style.addStyleSheetColors("btnPushFlat_PressedBk 0xFF236B44")
        btn.style.addStyleSheetColors("btnPushFlat_HotText 0xFFFFFFFF")
        btn.style.addStyleSheetColors("btnPushFlat_PressedText 0xFFFFFFFF")

        discard PushButton.create(bottom, "Narrow", {270, 96, 82})
        discard PushButton.create(bottom, "Wide command button", {380, 96, 260})
    }
}
