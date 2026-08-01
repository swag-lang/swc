#global public
#global namespace Input

using Math

// Tracks one gamepad and its transitions across updates.
struct Gamepad
{
    readonly
    {
        previousState: GamepadState     // State captured before the latest update.
        currentState:  GamepadState     // State captured by the latest update.
        connected:     bool             // Whether the indexed gamepad is currently connected.
    }

    index: u32     // Zero-based platform gamepad index.
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
        let newConnected = isConnected(.index)
        if !newConnected
        {
            if .connected do
                clear(me)
            .connected = false
        }
        else
        {
            .connected     = true
            .previousState = .currentState
            try .currentState.update(.index)
        }
    }

    // Reset the previous and current state
    mtd clear()
    {
        .previousState.clear()
        .currentState.clear()
    }

    // Determines whether specified input device button is pressed
    mtd isButtonPressed(button: GamepadButton)->bool
    {
        return .currentState.pressed[button]
    }

    // Determines whether specified input device button has just been pressed
    mtd isButtonJustPressed(button: GamepadButton)->bool
    {
        return .currentState.pressed[button] and !.previousState.pressed[button]
    }

    // Determines whether specified input device button is released (not pressed)
    mtd isButtonReleased(button: GamepadButton)->bool
    {
        return !.currentState.pressed[button]
    }

    // Determines whether specified input device button has just been released
    mtd isButtonJustReleased(button: GamepadButton)->bool
    {
        return !.currentState.pressed[button] and .previousState.pressed[button]
    }

    // Returns the normalized analog position of `control`.
    mtd position(control: GamepadButton)->Point
    {
        return .currentState.position[control]
    }

    // Set the vibration motor speeds
    mtd setVibration(left, right: f32) fail
    {
        try setVibration(.index, left, right)
    }
}
