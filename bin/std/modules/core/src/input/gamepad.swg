#global public
#global namespace Input

using Core.Errors, Math

// Tracks one gamepad and its transitions across updates.
struct Gamepad
{
    public readonly
    {
        previousState: GamepadState     // State captured before the latest update.
        currentState:  GamepadState     // State captured by the latest update.
        connected:     bool             // Whether the indexed gamepad is currently connected.
    }

    public index: u32     // Zero-based platform gamepad index.
}

impl Gamepad
{
    internal mtd setControlStates(control: GamepadButton, previousPressed, currentPressed: bool, previousPosition, currentPosition: Point)
    {
        .previousState.setPressed(control, previousPressed)
        .currentState.setPressed(control, currentPressed)
        .previousState.setPosition(control, previousPosition)
        .currentState.setPosition(control, currentPosition)
    }

    // Refreshes connection and control state for [[Core.Input.Gamepad.index]].
    mtd update() fail
    {
        if not isConnected(.index)
        {
            if .connected do
                .clear()
            .connected = false
        }
        else
        {
            .connected     = true
            .previousState = .currentState
            try .currentState.update(.index)
        }
    }

    // Resets the previous and the current state.
    mtd clear()
    {
        .previousState.clear()
        .currentState.clear()
    }

    // Returns whether `button` is pressed in the latest state.
    mtd isButtonPressed(button: GamepadButton)->bool => .currentState.pressed[button]

    // Returns whether `button` became pressed during the latest update.
    mtd isButtonJustPressed(button: GamepadButton)->bool => .currentState.pressed[button] and not .previousState.pressed[button]

    // Returns whether `button` is released in the latest state.
    mtd isButtonReleased(button: GamepadButton)->bool => not .currentState.pressed[button]

    // Returns whether `button` became released during the latest update.
    mtd isButtonJustReleased(button: GamepadButton)->bool => not .currentState.pressed[button] and .previousState.pressed[button]

    // Returns the normalized analog position of `control`.
    mtd position(control: GamepadButton)->Point => .currentState.position[control]

    // Sets the left and right rumble speeds, clamping finite values to 0 through 1.
    //
    // Fails for non-finite values or when the backend cannot access or drive this gamepad.
    mtd setVibration(left, right: f32) fail
    {
        try validateGamepadVibrationSpeeds(left, right)
        try setVibration(.index, left, right)
    }
}

internal func validateGamepadVibrationSpeeds(left, right: f32) fail
{
    if not Math.isFinite(left) or not Math.isFinite(right) do
        fail Errors.BadParameterError{"gamepad vibration speeds must be finite"}
}
