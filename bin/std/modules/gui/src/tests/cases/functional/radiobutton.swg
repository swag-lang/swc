#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const RadioButtonHeadless_Command = "RadioButtonHeadless.Command"

var RadioButtonHeadlessChangedCount: u32

func radioButtonHeadlessChanged(_: *RadioButton)
{
    RadioButtonHeadlessChangedCount += 1
}

// Clicking checks the radio once; a second click does not re-notify.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    RadioButtonHeadlessChangedCount = 0

    let radio = RadioButton.create(&host.root, "A", {20, 20, 120, 30}, RadioButtonHeadless_Command)
    radio.sigChanged += &radioButtonHeadlessChanged

    Swag.require(not radio.isChecked())

    host.click({40, 35})
    Swag.require(radio.isChecked())
    Swag.require(RadioButtonHeadlessChangedCount == 1)
    Swag.require(host.commandCount == 1)
    Swag.require(host.lastCommand == RadioButtonHeadless_Command)

    // Already checked: no new signal/command.
    host.click({40, 35})
    Swag.require(radio.isChecked())
    Swag.require(RadioButtonHeadlessChangedCount == 1)
    Swag.require(host.commandCount == 1)
}

// setChecked changes state silently (no signal/command).
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    RadioButtonHeadlessChangedCount = 0

    let radio = RadioButton.create(&host.root, "A", {20, 20, 120, 30})
    radio.sigChanged += &radioButtonHeadlessChanged

    radio.setChecked(true)
    Swag.require(radio.isChecked())
    radio.setChecked(false)
    Swag.require(not radio.isChecked())
    Swag.require(RadioButtonHeadlessChangedCount == 0)
    Swag.require(host.commandCount == 0)
}

// Two radios are independent windows; without a group id the framework leaves grouping to the
// caller (unchanged default).
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)
    host.recordCommands()

    let a = RadioButton.create(&host.root, "A", {20, 20, 120, 30})
    let b = RadioButton.create(&host.root, "B", {20, 60, 120, 30})

    Swag.require(host.wndAt({40, 35}) == a)
    Swag.require(host.wndAt({40, 75}) == b)

    host.click({40, 35})
    Swag.require(a.isChecked())
    Swag.require(not b.isChecked())

    // Ungrouped: both can be checked at once (grouping stays opt-in).
    b.setChecked(true)
    Swag.require(a.isChecked() and b.isChecked())
}

// Radios sharing a group id auto-uncheck each other, on both setChecked and a real click; a second
// group under the same parent stays independent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 280)
    let a = RadioButton.create(&host.root, "A", {20, 20, 160, 30})
    let b = RadioButton.create(&host.root, "B", {20, 60, 160, 30})
    let c = RadioButton.create(&host.root, "C", {20, 100, 160, 30})
    a.groupId, b.groupId, c.groupId = "density"

    a.setChecked(true)
    Swag.require(a.isChecked() and not b.isChecked() and not c.isChecked())

    // Clicking b checks it and unchecks a automatically.
    host.click({40, 75})
    Swag.require(not a.isChecked() and b.isChecked() and not c.isChecked())

    // A separate group under the same parent is not disturbed.
    let d = RadioButton.create(&host.root, "D", {20, 140, 160, 30})
    let e = RadioButton.create(&host.root, "E", {20, 180, 160, 30})
    d.groupId, e.groupId = "align"

    d.setChecked(true)
    Swag.require(d.isChecked() and b.isChecked())
    e.setChecked(true)
    Swag.require(not d.isChecked() and e.isChecked() and b.isChecked())
}

// Arrow navigation skips disabled options, as focus traversal does.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)

    let a = RadioButton.create(&host.root, "A", {20, 20, 160, 30})
    let b = RadioButton.create(&host.root, "B", {20, 60, 160, 30})
    let c = RadioButton.create(&host.root, "C", {20, 100, 160, 30})
    a.groupId, b.groupId, c.groupId = "choice"
    b.disable()
    a.setChecked(true)
    a.setFocus()

    host.keyPress(Input.Key.Down)
    Swag.require(not a.isChecked() and not b.isChecked() and c.isChecked())
    Swag.require(c.hasFocus())
}

// Arrow navigation skips hidden options, as focus traversal does.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 200)

    let a = RadioButton.create(&host.root, "A", {20, 20, 160, 30})
    let b = RadioButton.create(&host.root, "B", {20, 60, 160, 30})
    let c = RadioButton.create(&host.root, "C", {20, 100, 160, 30})
    a.groupId, b.groupId, c.groupId = "choice"
    b.hide()
    a.setChecked(true)
    a.setFocus()

    host.keyPress(Input.Key.Down)
    Swag.require(not a.isChecked() and not b.isChecked() and c.isChecked())
    Swag.require(c.hasFocus())
}
