#global public
#global namespace Input

// Tracks keyboard state, transitions, and configurable key repetition.
struct Keyboard
{
    public
    {
        readonly
        {
            previousState: KeyboardState     // State captured before the latest update.
            currentState:  KeyboardState     // State captured by the latest update.
        }

        initialRepeatDelayMs: u32  = 400      // Delay before the first repeated key press.
        repeatIntervalMs:     u32  = 50       // Delay between subsequent repeated key presses.
        repeatEnabled:        bool = true     // Whether held keys generate repeated press transitions.
    }

    isRepeating: [Key] bool
    pressedAtMs: [Key] u64
}

impl Keyboard
{
    // Test and backend hook kept out of the documented product surface.
    #[Swag.NoDoc]
    mtd setCurrentKeyState(key: Key, pressed: bool)
    {
        .currentState.setPressed(key, pressed)
    }

    // Presents every key of the current state as released.
    //
    // The next [[Core.Input.Keyboard.update]] resumes from the real device, so this quiets exactly
    // one update. Use it when the polled device must not reach the consumer, such as an
    // application whose keyboard belongs to another one for as long as it is not active.
    mtd releaseAllKeys()
    {
        .currentState.clear()
    }

    internal mtd setKeyStates(key: Key, previousPressed, currentPressed: bool)
    {
        .previousState.setPressed(key, previousPressed)
        .currentState.setPressed(key, currentPressed)
    }

    // Captures a new state, keeping the previous one, and repeats the presses of held keys.
    //
    // While `repeatEnabled` is set, a key held for `initialRepeatDelayMs`, then every
    // `repeatIntervalMs` after that, reports a new press through
    // [[Core.Input.Keyboard.isKeyJustPressed]].
    mtd update()
    {
        .previousState = .currentState
        .currentState.update()

        // A repetition clears the previous state of the key, which reads as a new press.
        let now = Time.monotonicMilliseconds()
        for key in Key
        {
            if not .currentState.isKeyPressed(key)
            {
                .isRepeating[key] = false
                .pressedAtMs[key] = 0
            }
            elif .repeatEnabled
            {
                // First pressed time
                if not .pressedAtMs[key] do
                    .pressedAtMs[key] = now

                // First repetition
                if not .isRepeating[key]
                {
                    if now - .pressedAtMs[key] >= .initialRepeatDelayMs
                    {
                        .isRepeating[key] = true
                        .pressedAtMs[key] = now
                        .previousState.setPressed(key, false)
                    }
                }
                elif now - .pressedAtMs[key] >= .repeatIntervalMs
                {
                    .pressedAtMs[key] = now
                    .previousState.setPressed(key, false)
                }
            }
        }
    }

    // Releases every key in both states and stops every repetition.
    mtd clear()
    {
        .previousState.clear()
        .currentState.clear()
        Memory.clear(&.isRepeating, #sizeof(.isRepeating))
        Memory.clear(&.pressedAtMs, #sizeof(.pressedAtMs))
    }

    // Returns whether `key` is pressed in the latest state.
    mtd isKeyPressed(key: Key)->bool => .currentState.pressed[key]

    // Returns whether `key` became pressed, or repeated, during the latest update.
    mtd isKeyJustPressed(key: Key)->bool => .currentState.pressed[key] and not .previousState.pressed[key]

    // Returns whether `key` is released in the latest state.
    mtd isKeyReleased(key: Key)->bool => not .currentState.pressed[key]

    // Returns whether `key` became released during the latest update.
    mtd isKeyJustReleased(key: Key)->bool => not .currentState.pressed[key] and .previousState.pressed[key]

    // Returns the modifier flags active in the latest state.
    mtd pressedModifiers()->KeyModifiers
    {
        var modifiers: KeyModifiers = .None
        if .isKeyPressed(.LShift) or .isKeyPressed(.RShift) do
            modifiers |= .Shift
        if .isKeyPressed(.LControl) or .isKeyPressed(.RControl) do
            modifiers |= .Control
        if .isKeyPressed(.LMenu) or .isKeyPressed(.RMenu) do
            modifiers |= .Alt
        return modifiers
    }
}
