#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

const CheckButtonHeadless_Command = "CheckButtonHeadless.Command"

var CheckButtonHeadlessChangedCount: u32

func checkButtonHeadlessChanged(btn: #nonull *CheckButton)
{
    discard btn
    CheckButtonHeadlessChangedCount += 1
}

// A click toggles the state from UnChecked to Checked and back.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Enable", {20, 20, 120, 30}, CheckButtonHeadless_Command)
    check.sigChanged += &checkButtonHeadlessChanged

    @assert(!check.isChecked())
    @assert(check.checked == .UnChecked)

    host.click({40, 35})
    @assert(check.isChecked())
    @assert(check.checked == .Checked)
    @assert(CheckButtonHeadlessChangedCount == 1)
    @assert(host.commandCount == 1)
    @assert(host.lastCommand == CheckButtonHeadless_Command)

    host.click({40, 35})
    @assert(!check.isChecked())
    @assert(check.checked == .UnChecked)
    @assert(CheckButtonHeadlessChangedCount == 2)
    @assert(host.commandCount == 2)

    host.shutdown()
}

// The ThreeState flag adds the Undefined state to the toggle cycle.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Tri", {20, 20, 120, 30})
    check.checkButtonFlags.add(.ThreeState)

    host.click({40, 35})
    @assert(check.checked == .Undefined)
    @assert(check.isUndefined())

    host.click({40, 35})
    @assert(check.checked == .Checked)
    @assert(check.isChecked())

    host.click({40, 35})
    @assert(check.checked == .UnChecked)

    host.shutdown()
}

// Space and Enter toggle the focused check button.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Key", {20, 20, 120, 30})
    check.sigChanged += &checkButtonHeadlessChanged
    host.focus(check)

    host.keyPress(Input.Key.Space)
    @assert(check.isChecked())
    @assert(CheckButtonHeadlessChangedCount == 1)

    host.keyPress(Input.Key.Return)
    @assert(!check.isChecked())
    @assert(CheckButtonHeadlessChangedCount == 2)

    host.shutdown()
}

// A disabled checkbutton ignores clicks.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Off", {20, 20, 120, 30})
    check.sigChanged += &checkButtonHeadlessChanged
    check.disable()

    host.click({40, 35})
    @assert(!check.isChecked())
    @assert(CheckButtonHeadlessChangedCount == 0)
    @assert(host.commandCount == 0)

    host.shutdown()
}
