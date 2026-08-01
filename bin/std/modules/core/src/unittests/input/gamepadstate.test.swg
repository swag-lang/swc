#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.GamepadState

    for [i] in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        state.setPressed(button, true)
        state.setPosition(button, {cast(f32) i + 0.25, cast(f32) i + 0.75})
    }

    state.clear()

    for [i] in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        @assert(!state.pressed[button])
        @assert(state.position[button] == Math.Point.Zero)
    }
}
