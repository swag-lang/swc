#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The value stays inside its bounds whatever sets it, and only the reader's changes notify.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)

    let stepper = Stepper.create(&host.root, {20, 20, 0, 0})
    Swag.assert(stepper.position.width == host.theme.metrics.stepper_Width)
    Swag.assert(stepper.position.height == host.theme.metrics.editBox_Height)

    var changes: u32
    stepper.sigChanged += func|changes = &changes|(_) { changes[] += 1 }

    stepper.setRange(0, 100)
    stepper.setValue(48)
    Swag.assert(stepper.value == 48 and changes == 0)
    stepper.setValue(500)
    Swag.assert(stepper.value == 100 and changes == 0)
    stepper.setRange(0, 10)
    Swag.assert(stepper.value == 10)

    stepper.setStep(3)
    stepper.stepBy(-1)
    Swag.assert(stepper.value == 7 and changes == 1)
    stepper.stepBy(-5)
    Swag.assert(stepper.value == 0 and changes == 2)
    stepper.stepBy(-1)
    Swag.assert(stepper.value == 0 and changes == 2)
}

// The two buttons step the value, and a button that reaches a bound becomes unavailable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)

    let stepper = Stepper.create(&host.root, {20, 20, 120, 0})
    stepper.setRange(0, 2)
    stepper.setValue(1)
    Swag.assert(stepper.decreaseBtn.isEnabled() and stepper.increaseBtn.isEnabled())
    Swag.assert(stepper.decreaseBtn.position.right() < stepper.increaseBtn.position.x)

    host.clickWnd(stepper.increaseBtn)
    Swag.assert(stepper.value == 2)
    Swag.assert(not stepper.increaseBtn.isEnabled() and stepper.decreaseBtn.isEnabled())

    host.clickWnd(stepper.decreaseBtn)
    host.clickWnd(stepper.decreaseBtn)
    Swag.assert(stepper.value == 0)
    Swag.assert(not stepper.decreaseBtn.isEnabled())
}

// Once the field holds the keyboard, the arrows step it, the page keys take ten steps, and Home
// and End reach the bounds.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)

    let stepper = Stepper.create(&host.root, {20, 20, 120, 0})
    stepper.setRange(-50, 50)
    host.focus(stepper)

    host.keyPress(.Up)
    host.keyPress(.Right)
    Swag.assert(stepper.value == 2)
    host.keyPress(.Down)
    Swag.assert(stepper.value == 1)
    host.keyPress(.PageUp)
    Swag.assert(stepper.value == 11)
    host.keyPress(.PageDown)
    host.keyPress(.PageDown)
    Swag.assert(stepper.value == -9)
    host.keyPress(.End)
    Swag.assert(stepper.value == 50)
    host.keyPress(.Home)
    Swag.assert(stepper.value == -50)
}

// The sum saturates at the bounds of the type instead of wrapping.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 80)

    let stepper = Stepper.create(&host.root, {20, 20, 120, 0})
    stepper.setValue(Swag.S64.Max - 1)
    stepper.setStep(10)
    stepper.stepBy(1)
    Swag.assert(stepper.value == Swag.S64.Max)
    stepper.setValue(Swag.S64.Min + 1)
    stepper.stepBy(-10)
    Swag.assert(stepper.value == Swag.S64.Min)
}
