#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const RadioButtonHeadless_Command = "RadioButtonHeadless.Command"

var RadioButtonHeadlessChangedCount: u32

func radioButtonHeadlessChanged(btn: *RadioButton)
{
    discard btn
    RadioButtonHeadlessChangedCount += 1
}

// Clicking checks the radio once; a second click does not re-notify.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    RadioButtonHeadlessChangedCount = 0

    let radio = RadioButton.create(&host.root, "A", {20, 20, 120, 30}, RadioButtonHeadless_Command)
    radio.sigChanged += &radioButtonHeadlessChanged

    Swag.assert(!radio.isChecked())

    host.click({40, 35})
    Swag.assert(radio.isChecked())
    Swag.assert(RadioButtonHeadlessChangedCount == 1)
    Swag.assert(host.commandCount == 1)
    Swag.assert(host.lastCommand == RadioButtonHeadless_Command)

    // Already checked: no new signal/command.
    host.click({40, 35})
    Swag.assert(radio.isChecked())
    Swag.assert(RadioButtonHeadlessChangedCount == 1)
    Swag.assert(host.commandCount == 1)
}

// setChecked changes state silently (no signal/command).
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    RadioButtonHeadlessChangedCount = 0

    let radio = RadioButton.create(&host.root, "A", {20, 20, 120, 30})
    radio.sigChanged += &radioButtonHeadlessChanged

    radio.setChecked(true)
    Swag.assert(radio.isChecked())
    radio.setChecked(false)
    Swag.assert(!radio.isChecked())
    Swag.assert(RadioButtonHeadlessChangedCount == 0)
    Swag.assert(host.commandCount == 0)
}

// Two radios are independent windows; without a group id the framework leaves grouping to the
// caller (unchanged default).
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    defer host.shutdown()
    host.recordCommands()

    let a = RadioButton.create(&host.root, "A", {20, 20, 120, 30})
    let b = RadioButton.create(&host.root, "B", {20, 60, 120, 30})

    Swag.assert(host.wndAt({40, 35}) == a)
    Swag.assert(host.wndAt({40, 75}) == b)

    host.click({40, 35})
    Swag.assert(a.isChecked())
    Swag.assert(!b.isChecked())

    // Ungrouped: both can be checked at once (grouping stays opt-in).
    b.setChecked(true)
    Swag.assert(a.isChecked() and b.isChecked())
}

// Radios sharing a group id auto-uncheck each other, on both setChecked and a real click; a second
// group under the same parent stays independent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 280)
    defer host.shutdown()
    let a = RadioButton.create(&host.root, "A", {20, 20, 160, 30})
    let b = RadioButton.create(&host.root, "B", {20, 60, 160, 30})
    let c = RadioButton.create(&host.root, "C", {20, 100, 160, 30})
    a.groupId, b.groupId, c.groupId = "density"

    a.setChecked(true)
    Swag.assert(a.isChecked() and !b.isChecked() and !c.isChecked())

    // Clicking b checks it and unchecks a automatically.
    host.click({40, 75})
    Swag.assert(!a.isChecked() and b.isChecked() and !c.isChecked())

    // A separate group under the same parent is not disturbed.
    let d = RadioButton.create(&host.root, "D", {20, 140, 160, 30})
    let e = RadioButton.create(&host.root, "E", {20, 180, 160, 30})
    d.groupId, e.groupId = "align"

    d.setChecked(true)
    Swag.assert(d.isChecked() and b.isChecked())
    e.setChecked(true)
    Swag.assert(!d.isChecked() and e.isChecked() and b.isChecked())
}
