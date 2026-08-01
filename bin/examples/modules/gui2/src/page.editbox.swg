using Core, Gui, Pixel

func createEditBoxPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let forms  = createPanel(parent, "Forms", "Square, round, flat and transparent edit boxes with placeholder notes.", layout.left)
    {
        var edit = EditBox.create(forms, "plain text", {24, 90, 180})
        edit.setPlaceholder("Square")

        edit = EditBox.create(forms, "", {240, 90, 200})
        edit.setForm(.RoundedRectangle)
        edit.setIcon(app.theme.icon24(ThemeIcons24.Search, 18))
        edit.setPlaceholder("Round search")

        edit = EditBox.create(forms, "", {24, 140, 180})
        edit.setForm(.Flat)
        edit.setPlaceholder("Flat note")

        edit = EditBox.create(forms, "transparent", {240, 140, 200})
        edit.setForm(.Transparent)
        edit.setPlaceholder("Transparent")

        edit = EditBox.create(forms, "right aligned text", {24, 190, 180})
        edit.updateFlags(.RightAligned)
        edit.setPlaceholder("Right aligned")

        edit = EditBox.create(forms, "0123456789", {240, 190, 200})
        edit.updateFlags(.RightAligned)
        edit.setPlaceholder("Right aligned")
    }

    let modes = createPanel(parent, "Input modes", "Numeric validation, max length, read-only and disabled fields.", layout.right)
    {
        var edit = EditBox.create(modes, "128", {24, 90, 130})
        edit.setSignedIntegerRange(-256, 256)
        edit.setUnit("px")
        edit.updateFlags(.RightAligned)
        edit.setPlaceholder("S64")

        edit = EditBox.create(modes, "FF", {180, 90, 130})
        edit.setHexadecimalRange()
        edit.setMaximumLength(4)
        edit.setPlaceholder("Hex")

        edit = EditBox.create(modes, "3.1415", {336, 90, 130})
        edit.setFloatingPointRange()
        edit.setPlaceholder("Float")

        edit = EditBox.create(modes, "Read only", {24, 140, 180})
        edit.updateFlags(.ReadOnly)

        edit = EditBox.create(modes, "Disabled", {240, 140, 180})
        edit.disable()
    }

    let extras = createPanel(parent, "Extras", "Clear buttons, units and focus borders exercise the small layout details.", layout.bottom)
    {
        var edit = EditBox.create(extras, "clear me", {24, 96, 220})
        edit.setForm(.RoundedRectangle)
        edit.updateFlags(.ClearButton)
        edit.setPlaceholder("Clear button")

        edit = EditBox.create(extras, "75", {280, 96, 120})
        edit.setUnsignedIntegerRange(0, 100)
        edit.setUnit("%")
        edit.updateFlags(.RightAligned)

        edit = EditBox.create(extras, "", {438, 96, 220})
        edit.setPlaceholder("Maximum 8 runes")
        edit.setMaximumLength(8)

        edit = EditBox.create(extras, "focus me", {696, 96, 220})
        edit.setForm(.RoundedRectangle)
        edit.setPlaceholder("Focus border")
    }
}
