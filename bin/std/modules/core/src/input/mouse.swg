#global public
#global namespace Input

using Math

// Tracks mouse position, buttons, transitions, and double-clicks across updates.
struct Mouse
{
    readonly
    {
        previousState: MouseState     // State captured before the latest update.
        currentState:  MouseState     // State captured by the latest update.
    }

    doubleClickTimeMs: u32 = 300     // Maximum interval recognized as a double-click.

    internal
    {
        doubleClicked: [MouseButton] bool
    }
}

impl Mouse
{
    // Test and backend hook kept out of the documented product surface.
    #[Swag.NoDoc]
    mtd setCurrentButtonState(button: MouseButton, pressed: bool)
    {
        .currentState.setPressed(button, pressed)
    }

    internal mtd setButtonStates(button: MouseButton, previousPressed, currentPressed, doubleClicked: bool)
    {
        .previousState.setPressed(button, previousPressed)
        .currentState.setPressed(button, currentPressed)
        .doubleClicked[button] = doubleClicked
    }

    // Test and backend hook kept out of the documented product surface.
    #[Swag.NoDoc]
    mtd setPositions(previous, current: Point)
    {
        .previousState.setPosition(previous)
        .currentState.setPosition(current)
    }

    internal mtd setPressMetadata(button: MouseButton, previousTimeMs, currentTimeMs: u64, previousPosition, currentPosition: Point)
    {
        .previousState.setPressMetadata(button, previousTimeMs, previousPosition)
        .currentState.setPressMetadata(button, currentTimeMs, currentPosition)
    }

    // Compute the current state of the mouse
    mtd update()
    {
        .previousState = .currentState
        .currentState.update()

        // Dbl click
        for v in MouseButton
        {
            .doubleClicked[v] = false
            if .currentState.pressed[v] and !.previousState.pressed[v] and .previousState.pressedTime[v]
            {
                if .currentState.pressedTime[v] - .previousState.pressedTime[v] < .doubleClickTimeMs
                {
                    if .currentState.pressedPos[v] == .previousState.pressedPos[v] do
                        .doubleClicked[v] = true
                }
            }
        }
    }

    // Reset the mouse state to its default value
    mtd clear()
    {
        .previousState.clear()
        .currentState.clear()
        Memory.clear(&.doubleClicked, #sizeof(.doubleClicked))
    }

    // Returns whether `button` completed a double-click during the latest update.
    mtd isButtonDoubleClick(button: MouseButton)->bool
    {
        return .doubleClicked[button]
    }

    // Returns whether `button` is currently pressed according to the operating system.
    func isButtonPressed(button: MouseButton)->bool
    {
        using MouseButton
        switch button
        {
        case .Left:     return Keyboard.isKeyPressed(Input.Key.LButton)
        case .Middle:   return Keyboard.isKeyPressed(Input.Key.MButton)
        case .Right:    return Keyboard.isKeyPressed(Input.Key.RButton)
        case .XButton1: return Keyboard.isKeyPressed(Input.Key.XButton1)
        case .XButton2: return Keyboard.isKeyPressed(Input.Key.XButton2)
        }

        return false
    }

    // Determines whether the specified mouse button is pressed
    mtd isButtonPressed(button: MouseButton)->bool
    {
        return .currentState.pressed[button]
    }

    // Determines whether the specified mouse button has just been pressed
    mtd isButtonJustPressed(button: MouseButton)->bool
    {
        return .currentState.pressed[button] and !.previousState.pressed[button]
    }

    // Determines whether the specified mouse button is released
    mtd isButtonReleased(button: MouseButton)->bool
    {
        return !.currentState.pressed[button]
    }

    // Determines whether the specified mouse button has just been released
    mtd isButtonJustReleased(button: MouseButton)->bool
    {
        return !.currentState.pressed[button] and .previousState.pressed[button]
    }

    // Returns the cursor position before the latest update.
    mtd previousPosition()->Point
    {
        return .previousState.position
    }

    // Returns the current cursor position.
    mtd position()->Point
    {
        return .currentState.position
    }

    // Returns the cursor movement since the previous update.
    mtd movement()->Point
    {
        return .currentState.position - .previousState.position
    }
}
