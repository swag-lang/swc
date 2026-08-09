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

    @assert(user.text() == "alice")
    @assert(password.position.y > user.position.y)
    @assert(dlg.buttons.count == 2)
    @assert(dlg.buttons[0].id == Dialog.BtnOk)
    @assert(dlg.buttons[1].id == Dialog.BtnCancel)

    var didClose: bool
    host.app.sigFrame += func|host = &host, didClose = &didClose|(app)
    {
        discard app
        if !dref didClose
        {
            @assert(host.clickModalButton(Dialog.BtnCancel))
            dref didClose = true
        }
    }
    @assert(dlg.doModal() == Dialog.BtnCancel)
    @assert(didClose)
}

// EditCtrl pairs a label with an editbox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)
    defer host.shutdown()
    let ctrl = EditCtrl.create(&host.root, "Name", "Bob", {0, 0, 240, 26})
    @assert(ctrl.label.text() == "Name")
    @assert(ctrl.edit.text() == "Bob")
    @assert(ctrl.label.position.width == ctrl.labelWidth)

    ctrl.edit.setText("Alice")
    @assert(ctrl.edit.text() == "Alice")

    ctrl.setLayoutMetrics(50, 0, 7)
    @assert(ctrl.labelWidth == 50 and ctrl.editWidth == 0 and ctrl.spacing == 7)
    @assert(ctrl.edit.position.width == 183)
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
        if !dref didSet
        {
            @assert(host.setModalEditText("Name", "Alice"))
            @assert(ctrl.edit.text() == "Alice")
            @assert(host.clickModalButton(Dialog.BtnOk))
            dref didSet = true
        }
    }

    let result = dlg.doModal()

    @assert(result == Dialog.BtnOk)
    @assert(didSet)
    @assert(ctrl.edit.text() == "Alice")
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
    @assert(ctrl.labelWidth == 50 and ctrl.valueWidth == 55 and ctrl.spacing == 6)
    @assert(!ctrl.autoValueWidth)
    ctrl.setFloatBounds(0, 100)

    ctrl.setValue(50)
    @assert(Math.abs(ctrl.value() - 50) < 0.01)
    @assert(ctrl.edit.text() == "50.00")
    @assert(CompositeSliderChangedCount == 1)
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
    @assert(Math.abs(ctrl.value() - 40) < 0.01)
    @assert(ctrl.edit.text() == "40")
}

// ComboCtrl pairs a label with a combobox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)
    defer host.shutdown()
    let ctrl = ComboCtrl.create(&host.root, "Mode", {0, 0, 240, 26})
    @assert(ctrl.label.text() == "Mode")

    ctrl.combo.addItem("One")
    ctrl.combo.addItem("Two")
    ctrl.combo.setSelectedIndex(1)
    host.pump()
    @assert(ctrl.combo.selectedIndex == 1)
    @assert(ctrl.combo.selectedItem()!.name.raw == "Two")

    ctrl.setLayoutMetrics(45, 0, 5)
    @assert(ctrl.labelWidth == 45 and ctrl.comboWidth == 0)
    @assert(ctrl.combo.position.width == 190)
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
    @assert(bar.kind == .Information)
    @assert(bar.flags.has(.Bottom))
    @assert(bar.label.text() == "Saved")

    bar.setText("Updated")
    bar.setKind(.Message)
    @assert(bar.label.text() == "Updated")
    @assert(bar.kind == .Message)

    bar.dismiss()
    @assert(CompositeInfoDismissedCount == 1)
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

    @assert(bar.label.flags.has(.Ellipsis))
    @assert(bar.label.name.boundRect.width > 0)
    @assert(bar.label.name.boundRect.right() <= bar.closeButton.position.x)
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
    @assert(picker.originalColor == Argb.Red)
    @assert(picker.selectedColor == Argb.Red)
    @assert(CompositeColorChangedCount == 1)

    picker.setOriginalColor(Argb.Green)
    picker.setMode(.RedGreen)
    @assert(picker.originalColor == Argb.Green)
    @assert(picker.mode == .RedGreen)
    @assert(picker.pickBox.mode == .RedGreen)
    @assert(picker.pickBar.mode == .BlueHorizontal)
    @assert(CompositeColorChangedCount == 1)

    picker.setColor(Argb.Red)
    @assert(CompositeColorChangedCount == 1)

    picker.setColor(Argb.Blue, notify: false)
    @assert(picker.selectedColor == Argb.Blue)
    @assert(CompositeColorChangedCount == 1)

    picker.setColorPreservingAlpha(Color.fromArgb(0x80402010))
    @assert(picker.selectedColor.a == 255)
    @assert(picker.selectedColor.r == 0x40)
    @assert(CompositeColorChangedCount == 2)
}
