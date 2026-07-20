#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

var CompositeSliderChangedCount: u32

func compositeSliderChanged(s: #nonull *SliderCtrl)
{
    discard s
    CompositeSliderChangedCount += 1
}

// EditCtrl pairs a label with an editbox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)

    let ctrl = EditCtrl.create(&host.root, "Name", "Bob", {0, 0, 240, 26})
    @assert(ctrl.label.getText() == "Name")
    @assert(ctrl.edit.getText() == "Bob")
    @assert(ctrl.label.position.width == ctrl.labelSize)

    ctrl.edit.setText("Alice")
    @assert(ctrl.edit.getText() == "Alice")

    host.shutdown()
}

// Headless modal helpers can fill an EditCtrl by label before validating.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

    let dlg = Dialog.createDialog(&host.surface, 260, 150, title: "Edit")
    dlg.addButton("OK", Dialog.BtnOk, true)
    let ctrl = EditCtrl.create(dlg, "Name", "Bob", {20, 20, 210, 26})

    var didSet: bool
    host.app.sigFrame += func|host = &host, ctrl, didSet = &didSet|(app)
    {
        if !dref didSet
        {
            @assert(host.setModalEditText("Name", "Alice"))
            @assert(ctrl.edit.getText() == "Alice")
            @assert(host.clickModalButton(Dialog.BtnOk))
            dref didSet = true
        }
    }

    let result = dlg.doModal()

    @assert(result == Dialog.BtnOk)
    @assert(didSet)
    @assert(ctrl.edit.getText() == "Alice")

    host.shutdown()
}

// SliderCtrl drives an embedded slider and mirrors the value into its editbox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 60)
    CompositeSliderChangedCount = 0

    let ctrl = SliderCtrl.create(&host.root, "Vol", {0, 0, 300, 30})
    ctrl.sigChanged += &compositeSliderChanged
    ctrl.setMinMaxF32(0, 100)

    ctrl.setValue(50)
    @assert(Math.abs(ctrl.getValue() - 50) < 0.01)
    @assert(ctrl.edit.getText() == "50.00")
    @assert(CompositeSliderChangedCount == 1)

    host.shutdown()
}

// SliderCtrl integer range formats the value box without decimals.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 60)

    let ctrl = SliderCtrl.create(&host.root, "N", {0, 0, 300, 30})
    ctrl.setMinMaxU64(0, 100)

    ctrl.setValue(40)
    @assert(Math.abs(ctrl.getValue() - 40) < 0.01)
    @assert(ctrl.edit.getText() == "40")

    host.shutdown()
}

// ComboCtrl pairs a label with a combobox.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 60)

    let ctrl = ComboCtrl.create(&host.root, "Mode", {0, 0, 240, 26})
    @assert(ctrl.label.getText() == "Mode")

    ctrl.combo.addItem("One")
    ctrl.combo.addItem("Two")
    ctrl.combo.selectItem(1)
    host.pump()
    @assert(ctrl.combo.selectedIdx == 1)
    @assert(ctrl.combo.getSelectedItem().name.raw == "Two")

    host.shutdown()
}
