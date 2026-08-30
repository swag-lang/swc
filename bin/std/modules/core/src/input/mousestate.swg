#global public
#global namespace Input

using Math

// Captures cursor position and button state at one update.
struct MouseState
{
    public readonly
    {
        pressed:     [MouseButton] bool      // Whether each button is pressed.
        pressedTime: [MouseButton] u64       // Monotonic millisecond timestamp of the latest press.
        pressedPos:  [MouseButton] Point     // Cursor position of the latest press.
        position:    Point                   // Cursor position in physical desktop pixels.
    }
}

// Represents a mouse state with cursor position and button press information
impl MouseState
{
    internal mtd setPressed(button: MouseButton, pressed: bool)
    {
        .pressed[button] = pressed
    }

    internal mtd setPosition(position: Point)
    {
        .position = position
    }

    internal mtd setPressMetadata(button: MouseButton, timeMs: u64, position: Point)
    {
        .pressedTime[button] = timeMs
        .pressedPos[button]  = position
    }

    // Compute the actual state of the mouse
    mtd update()
    {
        .position = mousePosition()

        for v in MouseButton
        {
            let b = .pressed[v]
            .pressed[v] = Mouse.isButtonPressed(v)
            if !b and .pressed[v]
            {
                .pressedTime[v] = Time.monotonicMilliseconds()
                .pressedPos[v]  = .position
            }
        }
    }

    // Reset the state to its default value
    mtd clear()
    {
        Swag.init(me, 1)
        .position = mousePosition()
    }
}
