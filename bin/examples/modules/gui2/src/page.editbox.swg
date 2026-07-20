using Core, Gui, Pixel

func createEditBoxPage(parent: #nonull *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let forms = createPanel(parent, "Forms", "Square, round, flat and transparent edit boxes with placeholder notes.", layout.left)
    {
        var edit = EditBox.create(forms, "plain text", {24, 90, 180})
        edit.setNote("Square")

        edit = EditBox.create(forms, "", {240, 90, 200})
        edit.setForm(.Round)
        edit.icon = app.theme.getIcon24(ThemeIcons24.Search, 18)
        edit.setNote("Round search")

        edit = EditBox.create(forms, "", {24, 140, 180})
        edit.setForm(.Flat)
        edit.setNote("Flat note")

        edit = EditBox.create(forms, "transparent", {240, 140, 200})
        edit.setForm(.Transparent)
        edit.setNote("Transparent")

        edit = EditBox.create(forms, "right aligned text", {24, 190, 180})
        edit.editBoxFlags |= .RightAlign
        edit.setNote("Right aligned")

        edit = EditBox.create(forms, "0123456789", {240, 190, 200})
        edit.editBoxFlags |= .RightAlign
        edit.setNote("Right aligned")
    }

    let modes = createPanel(parent, "Input modes", "Numeric validation, max length, read-only and disabled fields.", layout.right)
    {
        var edit = EditBox.create(modes, "128", {24, 90, 130})
        edit.setInputS64(-256, 256)
        edit.unit = "px"
        edit.editBoxFlags |= .RightAlign
        edit.setNote("S64")

        edit = EditBox.create(modes, "FF", {180, 90, 130})
        edit.setInputX64()
        edit.maxLength = 4
        edit.setNote("Hex")

        edit = EditBox.create(modes, "3.1415", {336, 90, 130})
        edit.setInputF64()
        edit.setNote("Float")

        edit = EditBox.create(modes, "Read only", {24, 140, 180})
        edit.editBoxFlags |= .ReadOnly

        edit = EditBox.create(modes, "Disabled", {240, 140, 180})
        edit.disable()
    }

    let extras = createPanel(parent, "Extras", "Clear buttons, units and focus borders exercise the small layout details.", layout.bottom)
    {
        var edit = EditBox.create(extras, "clear me", {24, 96, 220})
        edit.setForm(.Round)
        edit.editBoxFlags |= .ClearButton
        edit.setNote("Clear button")

        edit = EditBox.create(extras, "75", {280, 96, 120})
        edit.setInputU64(0, 100)
        edit.unit = "%"
        edit.editBoxFlags |= .RightAlign

        edit = EditBox.create(extras, "", {438, 96, 220})
        edit.setNote("Maximum 8 runes")
        edit.maxLength = 8

        edit = EditBox.create(extras, "focus me", {696, 96, 220})
        edit.setForm(.Round)
        edit.setNote("Focus border")
    }
}
