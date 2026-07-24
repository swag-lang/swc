#global public
#global namespace Input

// Represents one keyboard state
struct KeyboardState
{
    using native: KeyboardStateNative
    pressed:      [Key] bool
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
