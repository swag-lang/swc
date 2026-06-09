using Core, Gui, Pixel

func fillFlavorCombo(combo: *ComboBox)
{
    combo.addItem("Vanilla", "vanilla")
    combo.addItem("Chocolate", "chocolate", app.theme.getIcon24(ThemeIcons24.Filter, 18))
    combo.addItem("Pistachio", "pistachio")
    combo.addSeparator()
    combo.addItem("Seasonal special", "seasonal", app.theme.getIcon24(ThemeIcons24.More, 18))
}

func createComboBoxPage(parent: *Wnd)
{
    let left = createPanel(parent, "Select combos", "Regular popups with icons, separators and constrained height.", {0, 0, 500, 250})
    {
        var combo = ComboBox.create(left, {24, 94, 240})
        combo.maxHeightPopup = 150
        fillFlavorCombo(combo)
        combo.selectItem(1)

        combo = ComboBox.create(left, {24, 144, 240})
        combo.addItem("<b>Bold item", "bold")
        combo.addItem("<i>Italic item", "italic")
        combo.addItem("<p1>Palette item", "palette")
        combo.selectItem(0)
    }

    let right = createPanel(parent, "Editable and disabled", "Editable combos embed an EditBox; disabled combos keep their selected rendering.", {528, 0, 496, 250})
    {
        var combo = ComboBox.create(right, {24, 94, 260}, kind: .Edit)
        combo.addItem("Mercury", "mercury")
        combo.addItem("Venus", "venus")
        combo.addItem("Earth", "earth")
        combo.selectItem(2)

        combo = ComboBox.create(right, {24, 144, 260})
        combo.addItem("Disabled selected", "disabled")
        combo.selectItem(0)
        combo.disable()
    }

    let bottom = createPanel(parent, "Widths", "Narrow, normal and wide boxes exercise clipping and popup min width.", {0, 276, 1024, 248})
    {
        var combo = ComboBox.create(bottom, {24, 98, 120})
        combo.minWidthPopup = 220
        fillFlavorCombo(combo)
        combo.selectItem(0)

        combo = ComboBox.create(bottom, {190, 98, 240})
        fillFlavorCombo(combo)
        combo.selectItem(3)

        combo = ComboBox.create(bottom, {480, 98, 360})
        combo.addItem("A much longer selected label for clipping checks", "long")
        combo.addItem("Short", "short")
        combo.selectItem(0)
    }
}
