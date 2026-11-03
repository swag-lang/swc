#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var CompositeSliderChangedCount: u32
var CompositeInfoDismissedCount: u32
var CompositeColorChangedCount:  u32

func compositeSliderChanged(_: *SliderCtrl)
{
    CompositeSliderChangedCount += 1
}

func compositeInfoDismissed(_: *InfoBar)
{
    CompositeInfoDismissedCount += 1
}

func compositeColorChanged(_: *ColorPickerCtrl)
{
    CompositeColorChangedCount += 1
}

// FormDlg hosts typed fields and standard buttons without fixed coordinates.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)

    var options: FormDlgOptions
    options.title = "Credentials"
    let dlg      = FormDlg.create(&host.surface, options)
    let user     = dlg.form.addTextField("USER", "alice")
    let password = dlg.form.addPasswordField("PASSWORD")
    dlg.form.computeLayout()

    Swag.require(user.text() == "alice")
    Swag.require(password.position.y > user.position.y)
    Swag.require(dlg.buttons.count == 2)
    Swag.require(dlg.buttons[0].id == Dialog.BtnOk)
    Swag.require(dlg.buttons[1].id == Dialog.BtnCancel)
    Swag.require(dlg.contentView == dlg.form.parent)
    Swag.require(dlg.buttonBar.mode == .HorizontalEnd)
    Swag.require(dlg.buttonBar.spacing == dlg.themeMetrics().dialog_BtnPadding)
    Swag.require(dlg.padding.x == dlg.themeMetrics().dialog_Padding)
    Swag.require(dlg.contentView!.position.x == dlg.themeMetrics().dialog_Padding)

    var didClose: bool
    host.app.sigFrame += func|host = &host, didClose = &didClose|(_)
    {
        if not didClose[]
        {
            let modalButtonClicked = host.clickModalButton(Dialog.BtnCancel)
            Swag.require(modalButtonClicked)
            didClose[] = true
        }
    }

    let modalResult = dlg.doModal()
    Swag.require(modalResult == Dialog.BtnCancel)
    Swag.require(didClose)
}

// EditCtrl pairs a label with an editbox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)
    let ctrl = EditCtrl.create(&host.root, "Name", "Bob", {0, 0, 240, 26})
    Swag.require(ctrl.label.text() == "Name")
    Swag.require(ctrl.edit.text() == "Bob")
    Swag.require(ctrl.label.position.width == ctrl.labelWidth)

    ctrl.edit.setText("Alice")
    Swag.require(ctrl.edit.text() == "Alice")

    ctrl.setLayoutMetrics(50, 0, 7)
    Swag.require(ctrl.labelWidth == 50 and ctrl.editWidth == 0 and ctrl.spacing == 7)
    Swag.require(ctrl.edit.position.width == 183)
}

// Headless modal helpers can fill an EditCtrl by label before validating.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let dlg = Dialog.create(&host.surface, 260, 150, title: "Edit")
    dlg.addButton("OK", Dialog.BtnOk, true)
    let ctrl = EditCtrl.create(dlg, "Name", "Bob", {20, 20, 210, 26})

    var didSet: bool
    host.app.sigFrame += func|host = &host, ctrl, didSet = &didSet|(_)
    {
        if not didSet[]
        {
            Swag.require(host.setModalEditText("Name", "Alice"))
            Swag.require(ctrl.edit.text() == "Alice")
            let modalButtonClicked = host.clickModalButton(Dialog.BtnOk)
            Swag.require(modalButtonClicked)
            didSet[] = true
        }
    }

    let result = dlg.doModal()

    Swag.require(result == Dialog.BtnOk)
    Swag.require(didSet)
    Swag.require(ctrl.edit.text() == "Alice")
}

// SliderCtrl drives an embedded slider and mirrors the value into its editbox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 60)
    CompositeSliderChangedCount = 0

    let ctrl = SliderCtrl.create(&host.root, "Vol", {0, 0, 300, 30})
    ctrl.sigChanged += &compositeSliderChanged
    ctrl.setLayoutMetrics(50, 55, 6)
    ctrl.setAutomaticValueWidth(false)
    Swag.require(ctrl.labelWidth == 50 and ctrl.valueWidth == 55 and ctrl.spacing == 6)
    Swag.require(not ctrl.autoValueWidth)
    ctrl.setFloatBounds(0, 100)

    ctrl.setValue(50)
    Swag.require(Math.abs(ctrl.value() - 50) < 0.01)
    Swag.require(ctrl.edit.text() == "50.00")
    Swag.require(CompositeSliderChangedCount == 1)
}

// SliderCtrl integer range formats the value box without decimals.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 60)
    let ctrl = SliderCtrl.create(&host.root, "N", {0, 0, 300, 30})
    ctrl.setUnsignedBounds(0, 100)

    ctrl.setValue(40)
    Swag.require(Math.abs(ctrl.value() - 40) < 0.01)
    Swag.require(ctrl.edit.text() == "40")
}

// A typed reading commits on Enter, cancels on Escape, and rejects invalid input on blur.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 80)
    defer host.shutdown()
    let ctrl = SliderCtrl.create(&host.root, "Size", {0, 0, 300, 30})
    ctrl.edit.updateFlags(.ReleaseFocusOnEnterOrEscape)
    ctrl.setFloatBounds(1, 100)
    ctrl.setValue(40)

    ctrl.edit.setFocus()
    ctrl.edit.setText("72")
    host.keyPress(.Return)
    Swag.require(Math.abs(ctrl.value() - 72) < 0.01)

    ctrl.edit.setFocus()
    ctrl.edit.setText("18")
    host.keyPress(.Escape)
    Swag.require(Math.abs(ctrl.value() - 72) < 0.01)

    ctrl.edit.setFocus()
    ctrl.edit.setText("invalid")
    ctrl.setFocus()
    Swag.require(Math.abs(ctrl.value() - 72) < 0.01)
}

// ComboCtrl pairs a label with a combobox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)
    let ctrl = ComboCtrl.create(&host.root, "Mode", {0, 0, 240, 26})
    Swag.require(ctrl.label.text() == "Mode")

    ctrl.combo.addItem("One")
    ctrl.combo.addItem("Two")
    ctrl.combo.setSelectedIndex(1)
    host.pump()
    Swag.require(ctrl.combo.selectedIndex == 1)
    Swag.require(ctrl.combo.selectedItem()!.name.raw == "Two")

    ctrl.setLayoutMetrics(45, 0, 5)
    Swag.require(ctrl.labelWidth == 45 and ctrl.comboWidth == 0)
    Swag.require(ctrl.combo.position.width == 190)
}

// InfoBar exposes semantic state and emits one dismissal signal before destruction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    CompositeInfoDismissedCount = 0

    let bar = InfoBar.create(&host.root, "Saved", .Information, flags: .Bottom)
    bar.sigDismissed += &compositeInfoDismissed
    Swag.require(bar.kind == .Information)
    Swag.require(bar.flags.has(.Bottom))
    Swag.require(bar.label.text() == "Saved")

    bar.setText("Updated")
    bar.setKind(.Message)
    Swag.require(bar.label.text() == "Updated")
    Swag.require(bar.kind == .Message)

    bar.dismiss()
    Swag.require(CompositeInfoDismissedCount == 1)
}

// A dismissed notice leaves the way it came: it says so at once, closes its height, then goes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    host.setReducedMotion(false)
    CompositeInfoDismissedCount = 0

    let bar = InfoBar.create(&host.root, "Saved", .Information)
    bar.sigDismissed += &compositeInfoDismissed
    host.finishAnimations()
    Swag.require(bar.position.height == 40)

    bar.dismiss()
    bar.dismiss()
    Swag.require(CompositeInfoDismissedCount == 1)
    Swag.require(not bar.isPendingDestroy)

    host.finishAnimations()
    Swag.require(bar.isPendingDestroy)
}

// The information bar keeps its message clear of the dismiss button.
//
// The button is docked inside the label, so nothing but the text inset holds the two apart: a
// message longer than the band ran under the cross and off the right edge of the bar.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)

    let bar = InfoBar.create(&host.root, "A message far longer than the bar it is ever shown in", .Information)
    host.root.applyLayout()
    discard host.render()

    Swag.require(bar.label.flags.has(.Ellipsis))
    Swag.require(bar.label.name.boundRect.width > 0)
    Swag.require(bar.label.name.boundRect.right() <= bar.closeButton.position.x)
}

// ColorPickerCtrl exposes stable state and emits at most one signal per programmatic change.
#test
{
    var host: Testing.HeadlessHost
    host.setup(380, 360)
    CompositeColorChangedCount = 0

    let picker = ColorPickerCtrl.create(&host.root, {0, 0, 340, 330})
    picker.sigColorChanged += &compositeColorChanged

    picker.setColor(Argb.Red)
    Swag.require(picker.originalColor == Argb.Red)
    Swag.require(picker.selectedColor == Argb.Red)
    Swag.require(CompositeColorChangedCount == 1)

    picker.setOriginalColor(Argb.Green)
    picker.setMode(.RedGreen)
    Swag.require(picker.originalColor == Argb.Green)
    Swag.require(picker.mode == .RedGreen)
    Swag.require(picker.pickBox.mode == .RedGreen)
    Swag.require(picker.pickBar.mode == .BlueHorizontal)
    Swag.require(CompositeColorChangedCount == 1)

    picker.setColor(Argb.Red)
    Swag.require(CompositeColorChangedCount == 1)

    picker.setColor(Argb.Blue, notify: false)
    Swag.require(picker.selectedColor == Argb.Blue)
    Swag.require(CompositeColorChangedCount == 1)

    picker.setColorPreservingAlpha(Color.fromArgb(0x80402010))
    Swag.require(picker.selectedColor.a == 255)
    Swag.require(picker.selectedColor.r == 0x40)
    Swag.require(CompositeColorChangedCount == 2)
}
