#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var pad: Input.Gamepad

    for button in Input.GamepadButton
    {
        Swag.require(not pad.isButtonPressed(button))
        Swag.require(pad.isButtonReleased(button))
        Swag.require(not pad.isButtonJustPressed(button))
        Swag.require(not pad.isButtonJustReleased(button))
        Swag.require(pad.position(button) == Math.Point.Zero)
    }
}

#test
{
    var pad: Input.Gamepad

    for button in Input.GamepadButton
    {
        let i = cast(u32, button)
        let pos    = Math.Point{cast(f32, i) + 1.0, cast(f32, i) + 2.0}

        pad.setControlStates(button, false, true, Math.Point.Zero, pos)

        Swag.require(pad.isButtonPressed(button))
        Swag.require(not pad.isButtonReleased(button))
        Swag.require(pad.isButtonJustPressed(button))
        Swag.require(not pad.isButtonJustReleased(button))
        Swag.require(pad.position(button) == pos)

        pad.setControlStates(button, true, true, Math.Point.Zero, pos)
        Swag.require(pad.isButtonPressed(button))
        Swag.require(not pad.isButtonReleased(button))
        Swag.require(not pad.isButtonJustPressed(button))
        Swag.require(not pad.isButtonJustReleased(button))

        pad.setControlStates(button, true, false, Math.Point.Zero, pos)
        Swag.require(not pad.isButtonPressed(button))
        Swag.require(pad.isButtonReleased(button))
        Swag.require(not pad.isButtonJustPressed(button))
        Swag.require(pad.isButtonJustReleased(button))
    }
}

#test
{
    var pad: Input.Gamepad

    for button in Input.GamepadButton
    {
        pad.setControlStates(button, true, true, {1, 2}, {3, 4})
    }

    pad.clear()

    for button in Input.GamepadButton
    {
        Swag.require(not pad.previousState.pressed[button])
        Swag.require(not pad.currentState.pressed[button])
        Swag.require(pad.previousState.position[button] == Math.Point.Zero)
        Swag.require(pad.currentState.position[button] == Math.Point.Zero)
    }
}
