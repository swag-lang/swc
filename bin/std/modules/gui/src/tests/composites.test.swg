#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var CompositeSliderChangedCount: u32
var CompositeInfoDismissedCount: u32
var CompositeColorChangedCount:  u32

func compositeSliderChanged(s: *SliderCtrl)
{
    discard s
    CompositeSliderChangedCount += 1
}

func compositeInfoDismissed(bar: *InfoBar)
{
    discard bar
    CompositeInfoDismissedCount += 1
}

func compositeColorChanged(picker: *ColorPickerCtrl)
{
    discard picker
    CompositeColorChangedCount += 1
}

// FormDlg hosts typed fields and standard buttons without fixed coordinates.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()

    var options: FormDlgOptions
    options.title = "Credentials"
    let dlg      = FormDlg.create(&host.surface, options)
    let user     = dlg.form.addTextField("USER", "alice")
    let password = dlg.form.addPasswordField("PASSWORD")
    dlg.form.computeLayout()

    Swag.assert(user.text() == "alice")
    Swag.assert(password.position.y > user.position.y)
    Swag.assert(dlg.buttons.count == 2)
    Swag.assert(dlg.buttons[0].id == Dialog.BtnOk)
    Swag.assert(dlg.buttons[1].id == Dialog.BtnCancel)
    Swag.assert(dlg.contentView == dlg.form.parent)
    Swag.assert(dlg.buttonBar.mode == .HorizontalEnd)
    Swag.assert(dlg.buttonBar.spacing == dlg.themeMetrics().dialog_BtnPadding)
    Swag.assert(dlg.contentView!.padding.x == dlg.themeMetrics().dialog_Padding)
    Swag.assert(dlg.contentView!.padding.y == dlg.themeMetrics().dialog_Padding)

    var didClose: bool
    host.app.sigFrame += func|host = &host, didClose = &didClose|(app)
    {
        discard app
        if !didClose[]
        {
            Swag.assert(host.clickModalButton(Dialog.BtnCancel))
            didClose[] = true
        }
    }
    Swag.assert(dlg.doModal() == Dialog.BtnCancel)
    Swag.assert(didClose)
}

// EditCtrl pairs a label with an editbox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)
    defer host.shutdown()
    let ctrl = EditCtrl.create(&host.root, "Name", "Bob", {0, 0, 240, 26})
    Swag.assert(ctrl.label.text() == "Name")
    Swag.assert(ctrl.edit.text() == "Bob")
    Swag.assert(ctrl.label.position.width == ctrl.labelWidth)

    ctrl.edit.setText("Alice")
    Swag.assert(ctrl.edit.text() == "Alice")

    ctrl.setLayoutMetrics(50, 0, 7)
    Swag.assert(ctrl.labelWidth == 50 and ctrl.editWidth == 0 and ctrl.spacing == 7)
    Swag.assert(ctrl.edit.position.width == 183)
}

// Headless modal helpers can fill an EditCtrl by label before validating.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let dlg = Dialog.create(&host.surface, 260, 150, title: "Edit")
    dlg.addButton("OK", Dialog.BtnOk, true)
    let ctrl = EditCtrl.create(dlg, "Name", "Bob", {20, 20, 210, 26})

    var didSet: bool
    host.app.sigFrame += func|host = &host, ctrl, didSet = &didSet|(app)
    {
        if !didSet[]
        {
            Swag.assert(host.setModalEditText("Name", "Alice"))
            Swag.assert(ctrl.edit.text() == "Alice")
            Swag.assert(host.clickModalButton(Dialog.BtnOk))
            didSet[] = true
        }
    }

    let result = dlg.doModal()

    Swag.assert(result == Dialog.BtnOk)
    Swag.assert(didSet)
    Swag.assert(ctrl.edit.text() == "Alice")
}

// SliderCtrl drives an embedded slider and mirrors the value into its editbox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 60)
    defer host.shutdown()
    CompositeSliderChangedCount = 0

    let ctrl = SliderCtrl.create(&host.root, "Vol", {0, 0, 300, 30})
    ctrl.sigChanged += &compositeSliderChanged
    ctrl.setLayoutMetrics(50, 55, 6)
    ctrl.setAutomaticValueWidth(false)
    Swag.assert(ctrl.labelWidth == 50 and ctrl.valueWidth == 55 and ctrl.spacing == 6)
    Swag.assert(!ctrl.autoValueWidth)
    ctrl.setFloatBounds(0, 100)

    ctrl.setValue(50)
    Swag.assert(Math.abs(ctrl.value() - 50) < 0.01)
    Swag.assert(ctrl.edit.text() == "50.00")
    Swag.assert(CompositeSliderChangedCount == 1)
}

// SliderCtrl integer range formats the value box without decimals.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 60)
    defer host.shutdown()
    let ctrl = SliderCtrl.create(&host.root, "N", {0, 0, 300, 30})
    ctrl.setUnsignedBounds(0, 100)

    ctrl.setValue(40)
    Swag.assert(Math.abs(ctrl.value() - 40) < 0.01)
    Swag.assert(ctrl.edit.text() == "40")
}

// ComboCtrl pairs a label with a combobox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)
    defer host.shutdown()
    let ctrl = ComboCtrl.create(&host.root, "Mode", {0, 0, 240, 26})
    Swag.assert(ctrl.label.text() == "Mode")

    ctrl.combo.addItem("One")
    ctrl.combo.addItem("Two")
    ctrl.combo.setSelectedIndex(1)
    host.pump()
    Swag.assert(ctrl.combo.selectedIndex == 1)
    Swag.assert(ctrl.combo.selectedItem()!.name.raw == "Two")

    ctrl.setLayoutMetrics(45, 0, 5)
    Swag.assert(ctrl.labelWidth == 45 and ctrl.comboWidth == 0)
    Swag.assert(ctrl.combo.position.width == 190)
}

// InfoBar exposes semantic state and emits one dismissal signal before destruction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    defer host.shutdown()
    CompositeInfoDismissedCount = 0

    let bar = InfoBar.create(&host.root, "Saved", .Information, flags: .Bottom)
    bar.sigDismissed += &compositeInfoDismissed
    Swag.assert(bar.kind == .Information)
    Swag.assert(bar.flags.has(.Bottom))
    Swag.assert(bar.label.text() == "Saved")

    bar.setText("Updated")
    bar.setKind(.Message)
    Swag.assert(bar.label.text() == "Updated")
    Swag.assert(bar.kind == .Message)

    bar.dismiss()
    Swag.assert(CompositeInfoDismissedCount == 1)
}

// The information bar keeps its message clear of the dismiss button.
//
// The button is docked inside the label, so nothing but the text inset holds the two apart: a
// message longer than the band ran under the cross and off the right edge of the bar.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 120)
    defer host.shutdown()

    let bar = InfoBar.create(&host.root, "A message far longer than the bar it is ever shown in", .Information)
    host.root.applyLayout()
    discard host.render()

    Swag.assert(bar.label.flags.has(.Ellipsis))
    Swag.assert(bar.label.name.boundRect.width > 0)
    Swag.assert(bar.label.name.boundRect.right() <= bar.closeButton.position.x)
}

// ColorPickerCtrl exposes stable state and emits at most one signal per programmatic change.
#test
{
    var host: Testing.HeadlessHost
    host.setup(380, 360)
    defer host.shutdown()
    CompositeColorChangedCount = 0

    let picker = ColorPickerCtrl.create(&host.root, {0, 0, 340, 330})
    picker.sigColorChanged += &compositeColorChanged

    picker.setColor(Argb.Red)
    Swag.assert(picker.originalColor == Argb.Red)
    Swag.assert(picker.selectedColor == Argb.Red)
    Swag.assert(CompositeColorChangedCount == 1)

    picker.setOriginalColor(Argb.Green)
    picker.setMode(.RedGreen)
    Swag.assert(picker.originalColor == Argb.Green)
    Swag.assert(picker.mode == .RedGreen)
    Swag.assert(picker.pickBox.mode == .RedGreen)
    Swag.assert(picker.pickBar.mode == .BlueHorizontal)
    Swag.assert(CompositeColorChangedCount == 1)

    picker.setColor(Argb.Red)
    Swag.assert(CompositeColorChangedCount == 1)

    picker.setColor(Argb.Blue, notify: false)
    Swag.assert(picker.selectedColor == Argb.Blue)
    Swag.assert(CompositeColorChangedCount == 1)

    picker.setColorPreservingAlpha(Color.fromArgb(0x80402010))
    Swag.assert(picker.selectedColor.a == 255)
    Swag.assert(picker.selectedColor.r == 0x40)
    Swag.assert(CompositeColorChangedCount == 2)
}
