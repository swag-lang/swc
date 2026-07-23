using Core, Gui, Pixel

func bindRadioGroup(r0, r1, r2: *RadioButton)
{
    r0.sigChanged += func|r0, r1, r2|(btn)
    {
        r0.setChecked(true)
        r1.setChecked(false)
        r2.setChecked(false)
    }

    r1.sigChanged += func|r0, r1, r2|(btn)
    {
        r0.setChecked(false)
        r1.setChecked(true)
        r2.setChecked(false)
    }

    r2.sigChanged += func|r0, r1, r2|(btn)
    {
        r0.setChecked(false)
        r1.setChecked(false)
        r2.setChecked(true)
    }
}

func createRadioButtonPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left = createPanel(parent, "Exclusive group", "A small manual group checks the selected and unselected visual states.", layout.left)
    {
        let r0 = RadioButton.create(left, "Compact", {24, 90, 180})
        let r1 = RadioButton.create(left, "Comfortable", {24, 128, 180})
        let r2 = RadioButton.create(left, "Expanded", {24, 166, 180})
        r1.setChecked(true)
        bindRadioGroup(r0, r1, r2)
    }

    let right = createPanel(parent, "Alignment", "Radio buttons can also put the marker on the right side.", layout.right)
    {
        var radio = RadioButton.create(right, "Marker right", {24, 90, 250})
        radio.radioButtonFlags |= .RightAlign

        radio                  = RadioButton.create(right, "Selected right", {24, 128, 250})
        radio.radioButtonFlags |= .RightAlign
        radio.setChecked(true)

        radio                  = RadioButton.create(right, "Disabled selected", {24, 166, 250})
        radio.radioButtonFlags |= .RightAlign
        radio.setChecked(true)
        radio.disable()
    }

    let bottom = createPanel(parent, "States", "Disabled and large labels are grouped here to cover text clipping and inactive rendering.", layout.bottom)
    {
        var radio = RadioButton.create(bottom, "Normal idle radio button", {24, 94, 250})

        radio = RadioButton.create(bottom, "Disabled radio button", {24, 132, 250})
        radio.disable()

        radio = RadioButton.create(bottom, "Disabled selected radio button", {320, 94, 300})
        radio.setChecked(true)
        radio.disable()

        discard RadioButton.create(bottom, "Very long radio button label that must clip inside its bounds", {320, 132, 360})
    }
}
