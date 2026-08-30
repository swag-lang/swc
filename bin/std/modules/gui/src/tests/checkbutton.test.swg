#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const CheckButtonHeadless_Command = "CheckButtonHeadless.Command"

var CheckButtonHeadlessChangedCount: u32

func checkButtonHeadlessChanged(btn: *CheckButton)
{
    discard btn
    CheckButtonHeadlessChangedCount += 1
}

// A click toggles the state from Unchecked to Checked and back.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Enable", {20, 20, 120, 30}, CheckButtonHeadless_Command)
    check.sigChanged += &checkButtonHeadlessChanged

    Swag.assert(!check.isChecked())
    Swag.assert(check.state == .Unchecked)

    host.click({40, 35})
    Swag.assert(check.isChecked())
    Swag.assert(check.state == .Checked)
    Swag.assert(CheckButtonHeadlessChangedCount == 1)
    Swag.assert(host.commandCount == 1)
    Swag.assert(host.lastCommand == CheckButtonHeadless_Command)

    host.click({40, 35})
    Swag.assert(!check.isChecked())
    Swag.assert(check.state == .Unchecked)
    Swag.assert(CheckButtonHeadlessChangedCount == 2)
    Swag.assert(host.commandCount == 2)
}

// The TriState flag adds the Indeterminate state to the standard toggle cycle.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Tri", {20, 20, 120, 30})
    check.updateFlags(.TriState)

    host.click({40, 35})
    Swag.assert(check.state == .Checked)
    Swag.assert(check.isChecked())

    host.click({40, 35})
    Swag.assert(check.state == .Indeterminate)
    Swag.assert(check.isIndeterminate())

    host.click({40, 35})
    Swag.assert(check.state == .Unchecked)

    // Programmatic changes are silent and repaint without simulating input.
    check.setState(.Indeterminate)
    Swag.assert(check.isIndeterminate())
    Swag.assert(CheckButtonHeadlessChangedCount == 0)
}

// Space and Enter toggle the focused check button.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Key", {20, 20, 120, 30})
    check.sigChanged += &checkButtonHeadlessChanged
    host.focus(check)

    host.keyPress(Input.Key.Space)
    Swag.assert(check.isChecked())
    Swag.assert(CheckButtonHeadlessChangedCount == 1)

    host.keyPress(Input.Key.Return)
    Swag.assert(!check.isChecked())
    Swag.assert(CheckButtonHeadlessChangedCount == 2)
}

// A disabled checkbutton ignores clicks.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    defer host.shutdown()
    host.recordCommands()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Off", {20, 20, 120, 30})
    check.sigChanged += &checkButtonHeadlessChanged
    check.disable()

    host.click({40, 35})
    Swag.assert(!check.isChecked())
    Swag.assert(CheckButtonHeadlessChangedCount == 0)
    Swag.assert(host.commandCount == 0)
}
