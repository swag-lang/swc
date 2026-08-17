#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.GamepadState

    for i in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        state.setPressed(button, true)
        state.setPosition(button, {cast(f32) i + 0.25, cast(f32) i + 0.75})
    }

    state.clear()

    for i in @countof(Input.GamepadButton)
    {
        let button = cast(Input.GamepadButton) i
        @assert(!state.pressed[button])
        @assert(state.position[button] == Math.Point.Zero)
    }
}

#test
{
    using Input.GamepadButton

    var state: Input.GamepadState
    var raw:   Input.RawGamepadState
    raw.buttons      = .A | .DPadLeft | .RightShoulder
    raw.leftStickX   = -32768
    raw.leftStickY   = 32767
    raw.rightStickX  = 20000
    raw.leftTrigger  = 255
    raw.rightTrigger = 230
    state.update(raw)

    @assert(state.pressed[A])
    @assert(state.pressed[DPadLeft])
    @assert(state.pressed[RightShoulder])
    @assert(!state.pressed[B])
    @assert(state.position[LeftStick] == Math.Point{-1, 1})
    @assert(state.pressed[LeftThumbstickLeft])
    @assert(state.pressed[LeftThumbstickUp])
    @assert(!state.pressed[RightThumbstickRight])
    @assert(state.pressed[LeftTrigger])
    @assert(state.pressed[RightTrigger])

    raw.leftStickX   = cast(s16) (0.95 * 32767)
    raw.leftStickY   = 0
    raw.leftTrigger  = cast(u8) (0.95 * 255)
    raw.rightTrigger = 0
    state.update(raw)
    @assert(state.pressed[LeftThumbstickRight])
    @assert(state.pressed[LeftTrigger])
    @assert(!state.pressed[RightTrigger])

    raw.leftStickX  = cast(s16) (0.8 * 32767)
    raw.leftTrigger = cast(u8) (0.8 * 255)
    state.update(raw)
    @assert(state.pressed[LeftThumbstickRight])
    @assert(state.pressed[LeftTrigger])

    raw.leftStickX  = cast(s16) (0.6 * 32767)
    raw.leftTrigger = cast(u8) (0.6 * 255)
    state.update(raw)
    @assert(!state.pressed[LeftThumbstickRight])
    @assert(!state.pressed[LeftTrigger])
}
