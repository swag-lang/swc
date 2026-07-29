#global public
#global namespace Input

using Math

// Represents one mouse state
struct MouseState
{
    pressed:     [MouseButton] bool // Pressed associated with this value.
    pressedTime: [MouseButton] u32 // Pressed time associated with this value.
    pressedPos:  [MouseButton] Point // Pressed pos associated with this value.
    position:    Point // Position associated with this value.
}

// Represents a mouse state with cursor position and button press information
impl MouseState
{
    // Compute the actual state of the mouse
    mtd update()
    {
        .position = getMousePos()

        for v in MouseButton
        {
            let b = .pressed[v]
            .pressed[v] = Mouse.isButtonPressed(v)
            if !b and .pressed[v]
            {
                .pressedTime[v] = Time.nowMilliseconds()
                .pressedPos[v]  = .position
            }
        }
    }

    // Reset the state to its default value
    mtd clear()
    {
        Memory.clear(&.pressed, #sizeof(.pressed))
        .position = getMousePos()
    }
}
