#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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

// Two radios are independent windows; the framework leaves grouping to the caller.
#test
{
    var host: GuiHeadlessHost
    host.setup(240, 200)
    host.recordCommands()

    let a = RadioButton.create(&host.root, "A", {20, 20, 120, 30})
    let b = RadioButton.create(&host.root, "B", {20, 60, 120, 30})

    @assert(host.wndAt({40, 35}) == a)
    @assert(host.wndAt({40, 75}) == b)

    host.click({40, 35})
    @assert(a.checked)
    @assert(!b.checked)

    host.shutdown()
}
