#global public
#global namespace Input

// Captures the pressed keys at one update.
struct KeyboardState
{
    readonly
    {
        pressed: [Key] bool     // Whether each key is pressed.
    }

    internal
    {
        using native: KeyboardStateNative
    }
}

impl KeyboardState
{
    internal mtd setPressed(key: Key, pressed: bool)
    {
        .pressed[key] = pressed
    }

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
