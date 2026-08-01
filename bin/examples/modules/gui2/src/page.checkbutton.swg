using Core, Gui, Pixel

func createCheckButtonPage(parent: *Wnd)
{
    let layout = getPagePanelLayout(parent)
    let left   = createPanel(parent, "States", "The same CheckButton in unchecked, checked, undefined and disabled forms.", layout.left)
    {
        discard CheckButton.create(left, "Unchecked", {24, 90, 180})

        var check = CheckButton.create(left, "Checked", {24, 128, 180})
        check.setState(.Checked)

        check                  = CheckButton.create(left, "Undefined", {24, 166, 180})
        check.updateFlags(.TriState)
        check.setState(.Indeterminate)

        check         = CheckButton.create(left, "Disabled checked", {240, 90, 200})
        check.setState(.Checked)
        check.disable()

        check = CheckButton.create(left, "Disabled", {240, 128, 200})
        check.disable()
    }

    let right = createPanel(parent, "Alignment", "Right aligned boxes are useful inside property grids and inspector rows.", layout.right)
    {
        var check = CheckButton.create(right, "Box on the right", {24, 90, 250})
        check.updateFlags(.RightAligned)

        check                  = CheckButton.create(right, "Checked on the right", {24, 128, 250})
        check.updateFlags(.RightAligned)
        check.setState(.Checked)

        check                  = CheckButton.create(right, "Three-state right", {24, 166, 250})
        check.updateFlags(.RightAligned | .TriState)
        check.setState(.Indeterminate)
    }

    let bottom = createPanel(parent, "Interaction", "Click any option to update the feedback label and exercise signals.", layout.bottom)
    {
        let status = createText(bottom, "No option changed yet.", {24, 180, 420, 28})

        let grid = CheckButton.create(bottom, "Grid snapping", {24, 94, 210})
        grid.sigChanged += func|status|(btn) { status.setText(btn.isChecked() ? "Grid snapping enabled" : "Grid snapping disabled") }

        let guides = CheckButton.create(bottom, "Smart guides", {260, 94, 210})
        guides.setState(.Checked)
        guides.sigChanged += func|status|(btn) { status.setText(btn.isChecked() ? "Smart guides enabled" : "Smart guides disabled") }

        let mixed = CheckButton.create(bottom, "Mixed selection", {496, 94, 210})
        mixed.updateFlags(.TriState)
        mixed.setState(.Indeterminate)
        mixed.sigChanged += func|status|(btn) { status.setText(btn.isIndeterminate() ? "Selection is mixed" : "Selection is explicit") }
    }
}
