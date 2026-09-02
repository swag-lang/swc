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
    // The next [[Input.Keyboard.update]] resumes from the real device, so this quiets exactly
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

    // Compute current state of the keyboard (all keys)
    mtd update()
    {
        .previousState = .currentState
        .currentState.update()

        // Repetition
        let now = Time.monotonicMilliseconds()
        for key in Key
        {
            if !.currentState.isKeyPressed(key)
            {
                .isRepeating[key] = false
                .pressedAtMs[key] = 0
            }
            elif .repeatEnabled
            {
                // First pressed time
                if !.pressedAtMs[key] do
                    .pressedAtMs[key] = now

                // First repetition
                if !.isRepeating[key]
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

    // Reset the keyboard state
    mtd clear()
    {
        .previousState.clear()
        .currentState.clear()
        Memory.clear(&.isRepeating, #sizeof(.isRepeating))
        Memory.clear(&.pressedAtMs, #sizeof(.pressedAtMs))
    }

    // Determines whether given key is currently being pressed
    mtd isKeyPressed(key: Key)->bool
    {
        return .currentState.pressed[key]
    }

    // Determines whether given key has just been pressed
    mtd isKeyJustPressed(key: Key)->bool
    {
        return .currentState.pressed[key] and !.previousState.pressed[key]
    }

    // Determines whether given key is currently being released
    mtd isKeyReleased(key: Key)->bool
    {
        return !.currentState.pressed[key]
    }

    // Determines whether given key has just been released
    mtd isKeyJustReleased(key: Key)->bool
    {
        return !.currentState.pressed[key] and .previousState.pressed[key]
    }

    // Returns the modifier flags active in the latest state.
    mtd pressedModifiers()->KeyModifiers
    {
        var modifiers: Input.KeyModifiers = .None
        if .isKeyPressed(Input.Key.LShift) do
            modifiers |= .Shift
        if .isKeyPressed(Input.Key.RShift) do
            modifiers |= .Shift
        if .isKeyPressed(Input.Key.LControl) do
            modifiers |= .Control
        if .isKeyPressed(Input.Key.RControl) do
            modifiers |= .Control
        if .isKeyPressed(Input.Key.LMenu) do
            modifiers |= .Alt
        if .isKeyPressed(Input.Key.RMenu) do
            modifiers |= .Alt
        return modifiers
    }
}
