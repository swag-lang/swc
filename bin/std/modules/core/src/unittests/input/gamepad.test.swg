#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var pad: Input.Gamepad

    for [i] in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        @assert(!pad.isButtonPressed(button))
        @assert(pad.isButtonReleased(button))
        @assert(!pad.isButtonJustPressed(button))
        @assert(!pad.isButtonJustReleased(button))
        @assert(pad.position(button) == Math.Point.Zero)
    }
}

#test
{
    var pad: Input.Gamepad

    for [i] in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        let pos    = Math.Point{cast(f32) i + 1.0, cast(f32) i + 2.0}

        pad.setControlStates(button, false, true, Math.Point.Zero, pos)

        @assert(pad.isButtonPressed(button))
        @assert(!pad.isButtonReleased(button))
        @assert(pad.isButtonJustPressed(button))
        @assert(!pad.isButtonJustReleased(button))
        @assert(pad.position(button) == pos)

        pad.setControlStates(button, true, true, Math.Point.Zero, pos)
        @assert(pad.isButtonPressed(button))
        @assert(!pad.isButtonReleased(button))
        @assert(!pad.isButtonJustPressed(button))
        @assert(!pad.isButtonJustReleased(button))

        pad.setControlStates(button, true, false, Math.Point.Zero, pos)
        @assert(!pad.isButtonPressed(button))
        @assert(pad.isButtonReleased(button))
        @assert(!pad.isButtonJustPressed(button))
        @assert(pad.isButtonJustReleased(button))
    }
}

#test
{
    var pad: Input.Gamepad

    for [i] in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        pad.setControlStates(button, true, true, {1, 2}, {3, 4})
    }

    pad.clear()

    for [i] in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        @assert(!pad.previousState.pressed[button])
        @assert(!pad.currentState.pressed[button])
        @assert(pad.previousState.position[button] == Math.Point.Zero)
        @assert(pad.currentState.position[button] == Math.Point.Zero)
    }
}
