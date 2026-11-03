#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const CheckButtonHeadless_Command = "CheckButtonHeadless.Command"

var CheckButtonHeadlessChangedCount: u32

func checkButtonHeadlessChanged(_: *CheckButton)
{
    CheckButtonHeadlessChangedCount += 1
}

// A click toggles the state from Unchecked to Checked and back.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
    host.recordCommands()
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Enable", {20, 20, 120, 30}, CheckButtonHeadless_Command)
    check.sigChanged += &checkButtonHeadlessChanged

    Swag.assert(not check.isChecked())
    Swag.assert(check.state == .Unchecked)

    host.click({40, 35})
    Swag.assert(check.isChecked())
    Swag.assert(check.state == .Checked)
    Swag.assert(CheckButtonHeadlessChangedCount == 1)
    Swag.assert(host.commandCount == 1)
    Swag.assert(host.lastCommand == CheckButtonHeadless_Command)

    host.click({40, 35})
    Swag.assert(not check.isChecked())
    Swag.assert(check.state == .Unchecked)
    Swag.assert(CheckButtonHeadlessChangedCount == 2)
    Swag.assert(host.commandCount == 2)
}

// The TriState flag adds the Indeterminate state to the standard toggle cycle.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 120)
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
    CheckButtonHeadlessChangedCount = 0

    let check = CheckButton.create(&host.root, "Key", {20, 20, 120, 30})
    check.sigChanged += &checkButtonHeadlessChanged
    host.focus(check)

    host.keyPress(Input.Key.Space)
    Swag.assert(check.isChecked())
    Swag.assert(CheckButtonHeadlessChangedCount == 1)

    host.keyPress(Input.Key.Return)
    Swag.assert(not check.isChecked())
    Swag.assert(CheckButtonHeadlessChangedCount == 2)
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
    Swag.assert(not check.isChecked())
    Swag.assert(CheckButtonHeadlessChangedCount == 0)
    Swag.assert(host.commandCount == 0)
}

// A box fills and empties over a quick beat, and a radio dot leaves the option the choice left.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 160)
    host.setReducedMotion(false)

    let check = CheckButton.create(&host.root, "Enable", {20, 20, 120, 30})
    check.toggle()
    Swag.assert(check.isChecked() and check.markPresence < 1)
    host.finishAnimations()
    Swag.assert(check.markPresence == 1)
    check.setState(.Unchecked)
    host.finishAnimations()
    Swag.assert(check.markPresence == 0)

    let first  = RadioButton.create(&host.root, "First", {20, 60, 120, 30})
    let second = RadioButton.create(&host.root, "Second", {20, 100, 120, 30})
    first.groupId, second.groupId = "CheckButtonHeadless.Group"
    first.setChecked(true)
    host.finishAnimations()
    Swag.assert(first.markPresence == 1)
    second.selectFromUser()
    Swag.assert(first.markPresence == 1 and second.markPresence == 0)
    host.finishAnimations()
    Swag.assert(first.markPresence == 0 and second.markPresence == 1)
}
