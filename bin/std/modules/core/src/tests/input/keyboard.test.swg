#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var keyboard: Input.Keyboard

    for i in Input.Key.count
    {
        let key = cast(Input.Key) i
        Swag.assert(!keyboard.isKeyPressed(key))
        Swag.assert(keyboard.isKeyReleased(key))
        Swag.assert(!keyboard.isKeyJustPressed(key))
        Swag.assert(!keyboard.isKeyJustReleased(key))
    }
}

#test
{
    var keyboard: Input.Keyboard

    for i in Input.Key.count
    {
        let key = cast(Input.Key) i

        keyboard.setKeyStates(key, false, true)

        Swag.assert(keyboard.isKeyPressed(key))
        Swag.assert(!keyboard.isKeyReleased(key))
        Swag.assert(keyboard.isKeyJustPressed(key))
        Swag.assert(!keyboard.isKeyJustReleased(key))

        keyboard.setKeyStates(key, true, true)

        Swag.assert(keyboard.isKeyPressed(key))
        Swag.assert(!keyboard.isKeyReleased(key))
        Swag.assert(!keyboard.isKeyJustPressed(key))
        Swag.assert(!keyboard.isKeyJustReleased(key))

        keyboard.setKeyStates(key, true, false)

        Swag.assert(!keyboard.isKeyPressed(key))
        Swag.assert(keyboard.isKeyReleased(key))
        Swag.assert(!keyboard.isKeyJustPressed(key))
        Swag.assert(keyboard.isKeyJustReleased(key))
    }
}

#test
{
    var keyboard: Input.Keyboard

    Swag.assert(keyboard.pressedModifiers() == Input.KeyModifiers.None)

    keyboard.setKeyStates(.LShift, false, true)
    Swag.assert(keyboard.isKeyPressed(Input.Key.LShift))
    Swag.assert(!keyboard.isKeyPressed(Input.Key.RShift))
    Swag.assert(!keyboard.isKeyPressed(Input.Key.LControl))
    Swag.assert(!keyboard.isKeyPressed(Input.Key.RControl))
    Swag.assert(!keyboard.isKeyPressed(Input.Key.LMenu))
    Swag.assert(!keyboard.isKeyPressed(Input.Key.RMenu))
    Swag.assert(keyboard.pressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.setKeyStates(.RShift, false, true)
    Swag.assert(keyboard.pressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.setKeyStates(.LControl, false, true)
    Swag.assert(keyboard.pressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.setKeyStates(.RControl, false, true)
    Swag.assert(keyboard.pressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.setKeyStates(.LMenu, false, true)
    Swag.assert(keyboard.pressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))

    keyboard.setKeyStates(.RMenu, false, true)
    Swag.assert(keyboard.pressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))
}

#test
{
    var keyboard: Input.Keyboard

    for i in Input.Key.count
    {
        keyboard.setKeyStates(cast(Input.Key) i, true, true)
        keyboard.isRepeating[i] = true
        keyboard.pressedAtMs[i] = cast(u32) i + 1
    }

    keyboard.clear()

    for i in Input.Key.count
    {
        Swag.assert(!keyboard.previousState.pressed[i])
        Swag.assert(!keyboard.currentState.pressed[i])
        Swag.assert(!keyboard.isRepeating[i])
        Swag.assert(keyboard.pressedAtMs[i] == 0)
    }
}
