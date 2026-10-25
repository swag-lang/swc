using Core, Gui, Pixel

func createRadioButtonPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent,
                             "Exclusive group",
                             "A small manual group checks the selected and unselected visual states.",
                             layout.left)
    scope
    {
        let r0 = RadioButton.create(left, "Compact", Math.Rectangle{24, 90, 180})
        let r1 = RadioButton.create(left, "Comfortable", Math.Rectangle{24, 128, 180})
        let r2 = RadioButton.create(left, "Expanded", Math.Rectangle{24, 166, 180})
        r0.groupId, r1.groupId, r2.groupId = "density"
        r1.setChecked(true)
    }

    let right = createPanel(parent,
                            "Alignment",
                            "Radio buttons can also put the marker on the right side.",
                            layout.right)
    scope
    {
        var radio = RadioButton.create(right, "Marker right", Math.Rectangle{24, 90, 250})
        radio.updateFlags(.RightAligned)

        radio = RadioButton.create(right, "Selected right", Math.Rectangle{24, 128, 250})
        radio.updateFlags(.RightAligned)
        radio.setChecked(true)

        radio = RadioButton.create(right, "Disabled selected", Math.Rectangle{24, 166, 250})
        radio.updateFlags(.RightAligned)
        radio.setChecked(true)
        radio.disable()
    }

    let bottom = createPanel(parent,
                             "States",
                             "Disabled and large labels are grouped here to cover text clipping and inactive rendering.",
                             layout.bottom)
    scope
    {
        var radio = RadioButton.create(bottom, "Normal idle radio button", Math.Rectangle{24, 94, 250})

        radio = RadioButton.create(bottom, "Disabled radio button", Math.Rectangle{24, 132, 250})
        radio.disable()

        radio = RadioButton.create(bottom, "Disabled selected radio button", Math.Rectangle{320, 94, 300})
        radio.setChecked(true)
        radio.disable()

        discard RadioButton.create(bottom, "Very long radio button label that must clip inside its bounds", Math.Rectangle{320, 132, 360})
    }
}
