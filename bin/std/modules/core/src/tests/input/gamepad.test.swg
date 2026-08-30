#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var pad: Input.Gamepad

    for i in Input.GamepadButton.count
    {
        let button = cast(Input.GamepadButton) i
        Swag.assert(!pad.isButtonPressed(button))
        Swag.assert(pad.isButtonReleased(button))
        Swag.assert(!pad.isButtonJustPressed(button))
        Swag.assert(!pad.isButtonJustReleased(button))
        Swag.assert(pad.position(button) == Math.Point.Zero)
    }
}

#test
{
    var pad: Input.Gamepad

    for i in Input.GamepadButton.count
    {
        let button = cast(Input.GamepadButton) i
        let pos    = Math.Point{cast(f32) i + 1.0, cast(f32) i + 2.0}

        pad.setControlStates(button, false, true, Math.Point.Zero, pos)

        Swag.assert(pad.isButtonPressed(button))
        Swag.assert(!pad.isButtonReleased(button))
        Swag.assert(pad.isButtonJustPressed(button))
        Swag.assert(!pad.isButtonJustReleased(button))
        Swag.assert(pad.position(button) == pos)

        pad.setControlStates(button, true, true, Math.Point.Zero, pos)
        Swag.assert(pad.isButtonPressed(button))
        Swag.assert(!pad.isButtonReleased(button))
        Swag.assert(!pad.isButtonJustPressed(button))
        Swag.assert(!pad.isButtonJustReleased(button))

        pad.setControlStates(button, true, false, Math.Point.Zero, pos)
        Swag.assert(!pad.isButtonPressed(button))
        Swag.assert(pad.isButtonReleased(button))
        Swag.assert(!pad.isButtonJustPressed(button))
        Swag.assert(pad.isButtonJustReleased(button))
    }
}

#test
{
    var pad: Input.Gamepad

    for i in Input.GamepadButton.count
    {
        let button = cast(Input.GamepadButton) i
        pad.setControlStates(button, true, true, {1, 2}, {3, 4})
    }

    pad.clear()

    for i in Input.GamepadButton.count
    {
        let button = cast(Input.GamepadButton) i
        Swag.assert(!pad.previousState.pressed[button])
        Swag.assert(!pad.currentState.pressed[button])
        Swag.assert(pad.previousState.position[button] == Math.Point.Zero)
        Swag.assert(pad.currentState.position[button] == Math.Point.Zero)
    }
}
