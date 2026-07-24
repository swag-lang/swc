#global public
#global namespace Input

// Allows getting keystrokes from keyboard
struct Keyboard
{
    previousState: KeyboardState
    currentState:  KeyboardState
    pressedRepeat: [Key] bool
    pressedTime:   [Key] u32

    // Delay, in milliseconds, before a repeated key stroke starts
    pressedRepeatStartTimeMs: u32 = 400

    // Delay, in miliseconds, between two repeated key strokes
    pressedRepeatTimeMs: u32 = 50

    // Allow key stroke repetition if true
    canRepeat: bool = true
}

impl Keyboard
{
    // Compute current state of the keyboard (all keys)
    mtd update()
    {
        .previousState = .currentState
        .currentState.update()

        // Repetition
        let now = Time.nowMilliseconds()
        for key in Key
        {
            if !.currentState.isKeyPressed(key)
            {
                .pressedRepeat[key] = false
                .pressedTime[key]   = 0
            }
            elif .canRepeat
            {
                // First pressed time
                if !.pressedTime[key] do
                    .pressedTime[key] = now

                // First repetition
                if !.pressedRepeat[key]
                {
                    if now - .pressedTime[key] >= .pressedRepeatStartTimeMs
                    {
                        .pressedRepeat[key]         = true
                        .pressedTime[key]           = now
                        .previousState.pressed[key] = false
                    }
                }
                elif now - .pressedTime[key] >= .pressedRepeatTimeMs
                {
                    .pressedTime[key]           = now
                    .previousState.pressed[key] = false
                }
            }
        }
    }

    // Reset the keyboard state
    mtd clear()
    {
        .previousState.clear()
        .currentState.clear()
        Memory.clear(&.pressedRepeat, #sizeof(.pressedRepeat))
        Memory.clear(&.pressedTime, #sizeof(.pressedTime))
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

    // Returns the currently pressed key modifiers
    mtd getPressedModifiers()->KeyModifiers
    {
        var modifiers: Input.KeyModifiers = .Zero
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
