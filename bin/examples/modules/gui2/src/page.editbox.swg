using Core, Gui, Pixel

func createEditBoxPage(parent: *Wnd)
{
    const Inset = 24.0
    const Gap   = 16.0
    let layout    = getPagePanelLayout(parent)
    let halfWidth = (layout.left.width - 2 * Inset - Gap) * 0.5
    let rightX    = Inset + halfWidth + Gap
    let forms     = createPanel(parent,
                                "Forms",
                                "Square, round, flat and transparent edit boxes with placeholder notes.",
                                layout.left)
    scope
    {
        var edit = EditBox.create(forms, "plain text", {Inset, 90, halfWidth})
        edit.setPlaceholder("Square")

        edit = EditBox.create(forms, "", {rightX, 90, halfWidth})
        edit.setForm(.RoundedRectangle)
        edit.setIcon(app.theme.icon(ThemeIcons.Search, 18))
        edit.setPlaceholder("Round search")

        edit = EditBox.create(forms, "", {Inset, 140, halfWidth})
        edit.setForm(.Flat)
        edit.setPlaceholder("Flat note")

        edit = EditBox.create(forms, "transparent", {rightX, 140, halfWidth})
        edit.setForm(.Transparent)
        edit.setPlaceholder("Transparent")

        edit = EditBox.create(forms, "right aligned text", {Inset, 190, halfWidth})
        edit.updateFlags(.RightAligned)
        edit.setPlaceholder("Right aligned")

        edit = EditBox.create(forms, "0123456789", {rightX, 190, halfWidth})
        edit.updateFlags(.RightAligned)
        edit.setPlaceholder("Right aligned")
    }

    let modes = createPanel(parent,
                            "Input modes",
                            "Numeric validation, max length, read-only and disabled fields.",
                            layout.right)
    let numberWidth = (layout.right.width - 2 * Inset - 2 * Gap) / 3
    let numberStep  = numberWidth + Gap
    scope
    {
        var edit = EditBox.create(modes, "128", {Inset, 90, numberWidth})
        edit.setSignedIntegerRange(-256, 256)
        edit.setUnit("px")
        edit.updateFlags(.RightAligned)
        edit.setPlaceholder("S64")

        edit = EditBox.create(modes, "FF", {Inset + numberStep, 90, numberWidth})
        edit.setHexadecimalRange()
        edit.setMaximumLength(4)
        edit.setPlaceholder("Hex")

        edit = EditBox.create(modes, "3.1415", {Inset + 2 * numberStep, 90, numberWidth})
        edit.setFloatingPointRange()
        edit.setPlaceholder("Float")

        edit = EditBox.create(modes, "Read only", {Inset, 140, halfWidth})
        edit.updateFlags(.ReadOnly)

        edit = EditBox.create(modes, "Disabled", {rightX, 140, halfWidth})
        edit.disable()
    }

    let extras = createPanel(parent,
                             "Extras",
                             "Clear buttons, units and focus borders exercise the small layout details.",
                             layout.bottom)
    let extraWidth = (layout.bottom.width - 2 * Inset - 3 * Gap) / 4
    let extraStep  = extraWidth + Gap
    scope
    {
        var edit = EditBox.create(extras, "clear me", {Inset, 96, extraWidth})
        edit.setForm(.RoundedRectangle)
        edit.updateFlags(.ClearButton)
        edit.setPlaceholder("Clear button")

        edit = EditBox.create(extras, "75", {Inset + extraStep, 96, extraWidth})
        edit.setUnsignedIntegerRange(0, 100)
        edit.setUnit("%")
        edit.updateFlags(.RightAligned)

        edit = EditBox.create(extras, "", {Inset + 2 * extraStep, 96, extraWidth})
        edit.setPlaceholder("Maximum 8 runes")
        edit.setMaximumLength(8)

        edit = EditBox.create(extras, "focus me", {Inset + 3 * extraStep, 96, extraWidth})
        edit.setForm(.RoundedRectangle)
        edit.setPlaceholder("Focus border")
    }
}
