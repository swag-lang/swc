#global #if #command == Swag.CompilerCommand.Test
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
    host.recordCommands()
    RadioButtonHeadlessChangedCount = 0

    let radio = RadioButton.create(&host.root, "A", {20, 20, 120, 30}, RadioButtonHeadless_Command)
    radio.sigChanged += &radioButtonHeadlessChanged

    @assert(!radio.checked)

    host.click({40, 35})
    @assert(radio.checked)
    @assert(RadioButtonHeadlessChangedCount == 1)
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == RadioButtonHeadless_Command)

    // Already checked: no new signal/command.
    host.click({40, 35})
    @assert(radio.checked)
    @assert(RadioButtonHeadlessChangedCount == 1)
    @assert(host.commandCount == 1)

    host.shutdown()
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
    @assert(radio.checked)
    radio.setChecked(false)
    @assert(!radio.checked)
    @assert(RadioButtonHeadlessChangedCount == 0)
    @assert(host.commandCount == 0)

    host.shutdown()
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

    @assert(host.wndAt({40, 35}) == a)
    @assert(host.wndAt({40, 75}) == b)

    host.click({40, 35})
    @assert(a.checked)
    @assert(!b.checked)

    // Ungrouped: both can be checked at once (grouping stays opt-in).
    b.setChecked(true)
    @assert(a.checked and b.checked)

    host.shutdown()
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
    a.group, b.group, c.group = "density"

    a.setChecked(true)
    @assert(a.checked and !b.checked and !c.checked)

    // Clicking b checks it and unchecks a automatically.
    host.click({40, 75})
    @assert(!a.checked and b.checked and !c.checked)

    // A separate group under the same parent is not disturbed.
    let d = RadioButton.create(&host.root, "D", {20, 140, 160, 30})
    let e = RadioButton.create(&host.root, "E", {20, 180, 160, 30})
    d.group, e.group = "align"

    d.setChecked(true)
    @assert(d.checked and b.checked)
    e.setChecked(true)
    @assert(!d.checked and e.checked and b.checked)

    host.shutdown()
}
