using Core, Gui, Pixel

func createPushButtonPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "Forms",
                             "One primary action, the secondary and quiet forms beside it, and the destructive one that says what it removes.",
                             layout.left)
    scope
    {
        discard PushButton.create(left, "Open", {24, 88, 150}, null, .Default)
        discard PushButton.create(left, "Cancel", {190, 88, 150})
        discard PushButton.create(left, "Later", {24, 136, 150}, null, .Flat)
        discard PushButton.create(left, "Delete", {190, 136, 150}, null, .Destructive)

        // A mode the reader turned on is chosen, not acted on: it wears Arc beside the primary.
        discard PushButton.create(left, "Snap On", {24, 184, 150}, null, .Alternate)

        let export = PushButton.create(left, "Export", {190, 184, 150})
        export.setIcon(app.theme.icon(ThemeIcons.Download, 16))
    }

    let right = createPanel(parent,
                            "States",
                            "Hover and press are left to the pointer; disabled buttons stand at the weaker ink.",
                            layout.right)
    scope
    {
        let status = createText(right, "No button pressed yet.", {24, 184, 380, 28}, .SecondaryText)

        var btn = PushButton.create(right, "Press Me", {24, 88, 150})
        btn.sigPressed += func|status|(_) { status.setText("Pressed: the secondary button.") }

        btn = PushButton.create(right, "Disabled", {190, 88, 150})
        btn.disable()

        btn = PushButton.create(right, "Long Label Clipped Cleanly", {24, 136, 210})
        btn.sigPressed += func|status|(_) { status.setText("Pressed: the long label.") }

        btn        = PushButton.create(right, "Help Cursor", {250, 136, 150})
        btn.cursor = Cursor.from(CursorShape.Help)
    }

    let bottom = createPanel(parent,
                             "Widths",
                             "A button is at least as wide as the theme says and widens to its caption rather than clipping it.",
                             layout.bottom)
    scope
    {
        discard PushButton.create(bottom, "Narrow", {24, 88, 82})

        let fitted = PushButton.create(bottom, "Fitted to Its Caption", {130, 88, 150})
        fitted.fitWidthToLabel(fitted.themeMetrics().btnPush_Width)

        discard PushButton.create(bottom, "Wide Command Button", {130 + fitted.position.width + 24, 88, 260})
    }
}
