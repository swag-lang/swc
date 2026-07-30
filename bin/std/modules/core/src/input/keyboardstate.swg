#global public
#global namespace Input

// Represents one keyboard state
struct KeyboardState
{
    using native: KeyboardStateNative     // Embedded native state.
    pressed:      [Key] bool              // Pressed associated with this value.
}

impl KeyboardState
{
    // Compute current keyboard state
    mtd update()
    {
        .updateNative()
        for key in Key do
            .pressed[key] = .native.isKeyPressed(key)
    }

    // Reset keyboard state
    mtd clear()
    {
        Memory.clear(&.pressed, #sizeof(.pressed))
    }
}
