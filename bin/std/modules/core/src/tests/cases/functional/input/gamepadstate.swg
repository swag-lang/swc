#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.GamepadState

    for button in Input.GamepadButton
    {
        let i = cast(u32, button)
        state.setPressed(button, true)
        state.setPosition(button, Math.Point{cast(f32, i) + 0.25, cast(f32, i) + 0.75})
    }

    state.clear()

    for button in Input.GamepadButton
    {
        Swag.require(not state.pressed[button])
        Swag.require(state.position[button] == Math.Point.Zero)
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

    Swag.require(state.pressed[A])
    Swag.require(state.pressed[DPadLeft])
    Swag.require(state.pressed[RightShoulder])
    Swag.require(not state.pressed[B])
    Swag.require(state.position[LeftStick] == Math.Point{-1, 1})
    Swag.require(state.pressed[LeftThumbstickLeft])
    Swag.require(state.pressed[LeftThumbstickUp])
    Swag.require(not state.pressed[RightThumbstickRight])
    Swag.require(state.pressed[LeftTrigger])
    Swag.require(state.pressed[RightTrigger])

    raw.leftStickX   = cast(s16, (0.95 * 32767))
    raw.leftStickY   = 0
    raw.leftTrigger  = cast(u8, (0.95 * 255))
    raw.rightTrigger = 0
    state.update(raw)
    Swag.require(state.pressed[LeftThumbstickRight])
    Swag.require(state.pressed[LeftTrigger])
    Swag.require(not state.pressed[RightTrigger])

    raw.leftStickX  = cast(s16, (0.8 * 32767))
    raw.leftTrigger = cast(u8, (0.8 * 255))
    state.update(raw)
    Swag.require(state.pressed[LeftThumbstickRight])
    Swag.require(state.pressed[LeftTrigger])

    raw.leftStickX  = cast(s16, (0.6 * 32767))
    raw.leftTrigger = cast(u8, (0.6 * 255))
    state.update(raw)
    Swag.require(not state.pressed[LeftThumbstickRight])
    Swag.require(not state.pressed[LeftTrigger])
}
