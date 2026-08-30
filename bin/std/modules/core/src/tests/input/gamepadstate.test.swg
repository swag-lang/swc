#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.GamepadState

    for i in Input.GamepadButton.count
    {
        let button = cast(Input.GamepadButton) i
        state.setPressed(button, true)
        state.setPosition(button, {cast(f32) i + 0.25, cast(f32) i + 0.75})
    }

    state.clear()

    for i in Input.GamepadButton.count
    {
        let button = cast(Input.GamepadButton) i
        Swag.assert(!state.pressed[button])
        Swag.assert(state.position[button] == Math.Point.Zero)
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

    Swag.assert(state.pressed[A])
    Swag.assert(state.pressed[DPadLeft])
    Swag.assert(state.pressed[RightShoulder])
    Swag.assert(!state.pressed[B])
    Swag.assert(state.position[LeftStick] == Math.Point{-1, 1})
    Swag.assert(state.pressed[LeftThumbstickLeft])
    Swag.assert(state.pressed[LeftThumbstickUp])
    Swag.assert(!state.pressed[RightThumbstickRight])
    Swag.assert(state.pressed[LeftTrigger])
    Swag.assert(state.pressed[RightTrigger])

    raw.leftStickX   = cast(s16) (0.95 * 32767)
    raw.leftStickY   = 0
    raw.leftTrigger  = cast(u8) (0.95 * 255)
    raw.rightTrigger = 0
    state.update(raw)
    Swag.assert(state.pressed[LeftThumbstickRight])
    Swag.assert(state.pressed[LeftTrigger])
    Swag.assert(!state.pressed[RightTrigger])

    raw.leftStickX  = cast(s16) (0.8 * 32767)
    raw.leftTrigger = cast(u8) (0.8 * 255)
    state.update(raw)
    Swag.assert(state.pressed[LeftThumbstickRight])
    Swag.assert(state.pressed[LeftTrigger])

    raw.leftStickX  = cast(s16) (0.6 * 32767)
    raw.leftTrigger = cast(u8) (0.6 * 255)
    state.update(raw)
    Swag.assert(!state.pressed[LeftThumbstickRight])
    Swag.assert(!state.pressed[LeftTrigger])
}
