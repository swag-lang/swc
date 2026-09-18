#global public
#global namespace Input

// Captures the pressed keys at one update.
struct KeyboardState
{
    public readonly
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

    // Captures the current state of every key.
    mtd update()
    {
        .updateNative()
        for key in Key do
            .pressed[key] = .native.isKeyPressed(key)
    }

    // Marks every key as released.
    mtd clear()
    {
        Memory.clear(&.pressed, #sizeof(.pressed))
    }
}
