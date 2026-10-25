using Core, Gui, Pixel

func createPushButtonPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "Forms",
                             "The same command rendered with the standard push button forms.",
                             layout.left)
    scope
    {
        var btn = PushButton.create(left, "Normal", Math.Rectangle{22, 92, 150})
        btn.setIcon(app.theme.icon(ThemeIcons.Play, 18))

        btn = PushButton.create(left, "Default", Math.Rectangle{190, 92, 150})
        btn.setForm(.Default)
        btn.setIcon(app.theme.icon(ThemeIcons.Save, 18))

        btn = PushButton.create(left, "Flat", Math.Rectangle{22, 142, 150})
        btn.setForm(.Flat)
        btn.setIcon(app.theme.icon(ThemeIcons.Search, 18))

        btn = PushButton.create(left, "Strong", Math.Rectangle{190, 142, 150})
        btn.setForm(.Strong)
        btn.setIcon(app.theme.icon(ThemeIcons.Download, 18))
    }

    let right = createPanel(parent,
                            "States",
                            "Hot/pressed states are interactive; disabled and long text variants check clipping.",
                            layout.right)
    scope
    {
        let status = createText(right, "No button pressed yet.", Math.Rectangle{22, 190, 430, 28})

        var btn = PushButton.create(right, "Press me", Math.Rectangle{22, 92, 150})
        btn.sigPressed += func|status|(_) { status.setText("Pressed: standard button") }

        btn = PushButton.create(right, "Disabled", Math.Rectangle{190, 92, 150})
        btn.disable()

        btn = PushButton.create(right, "Long label clipped cleanly", Math.Rectangle{22, 142, 210})
        btn.setForm(.Default)
        btn.sigPressed += func|status|(_) { status.setText("Pressed: long label button") }

        btn        = PushButton.create(right, "Help cursor", Math.Rectangle{250, 142, 150})
        btn.cursor = Cursor.from(CursorShape.Help)
    }

    let bottom = createPanel(parent,
                             "Style override",
                             "A flat button with custom colors, used as a compact visual regression target.",
                             layout.bottom)
    scope
    {
        var btn = PushButton.create(bottom, "Custom flat action", Math.Rectangle{22, 96, 220})
        btn.setForm(.Flat)
        btn.setIcon(app.theme.icon(ThemeIcons.Filter, 18))
        btn.style.addStyleSheetColors("btnPushFlat_HotBk 0xFF2F8F5B")
        btn.style.addStyleSheetColors("btnPushFlat_PressedBk 0xFF236B44")
        btn.style.addStyleSheetColors("btnPushFlat_HotText 0xFFFFFFFF")
        btn.style.addStyleSheetColors("btnPushFlat_PressedText 0xFFFFFFFF")

        btn = PushButton.create(bottom, "Narrow", Math.Rectangle{270, 96, 82})

        btn = PushButton.create(bottom, "Wide command button", Math.Rectangle{380, 96, 260})
    }
}
