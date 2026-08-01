#global public
#global namespace Input

using Math

// Captures the digital and analog state of a gamepad at one update.
struct GamepadState
{
    readonly
    {
        pressed:  [GamepadButton] bool      // Whether each button or thresholded control is active.
        position: [GamepadButton] Point     // Normalized analog positions in the range -1 through 1.
    }
}

impl GamepadState
{
    internal mtd setPressed(button: GamepadButton, pressed: bool)
    {
        .pressed[button] = pressed
    }

    internal mtd setPosition(control: GamepadButton, position: Point)
    {
        .position[control] = position
    }

    // Reset state to its default value
    mtd clear()
    {
        Memory.clear(&.pressed, #sizeof(.pressed))
        Memory.clear(&.position, #sizeof(.position))
    }
}
