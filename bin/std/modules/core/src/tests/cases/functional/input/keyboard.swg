#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var keyboard: Input.Keyboard

    for i in Input.Key.count
    {
        let key = Input.keyFromStorageIndex(i)
        Swag.require(not keyboard.isKeyPressed(key))
        Swag.require(keyboard.isKeyReleased(key))
        Swag.require(not keyboard.isKeyJustPressed(key))
        Swag.require(not keyboard.isKeyJustReleased(key))
    }
}

#test
{
    var keyboard: Input.Keyboard

    for i in Input.Key.count
    {
        let key = Input.keyFromStorageIndex(i)

        keyboard.setKeyStates(key, false, true)

        Swag.require(keyboard.isKeyPressed(key))
        Swag.require(not keyboard.isKeyReleased(key))
        Swag.require(keyboard.isKeyJustPressed(key))
        Swag.require(not keyboard.isKeyJustReleased(key))

        keyboard.setKeyStates(key, true, true)

        Swag.require(keyboard.isKeyPressed(key))
        Swag.require(not keyboard.isKeyReleased(key))
        Swag.require(not keyboard.isKeyJustPressed(key))
        Swag.require(not keyboard.isKeyJustReleased(key))

        keyboard.setKeyStates(key, true, false)

        Swag.require(not keyboard.isKeyPressed(key))
        Swag.require(keyboard.isKeyReleased(key))
        Swag.require(not keyboard.isKeyJustPressed(key))
        Swag.require(keyboard.isKeyJustReleased(key))
    }
}

#test
{
    var keyboard: Input.Keyboard

    Swag.require(keyboard.pressedModifiers() == Input.KeyModifiers.None)

    keyboard.setKeyStates(.LShift, false, true)
    Swag.require(keyboard.isKeyPressed(Input.Key.LShift))
    Swag.require(not keyboard.isKeyPressed(Input.Key.RShift))
    Swag.require(not keyboard.isKeyPressed(Input.Key.LControl))
    Swag.require(not keyboard.isKeyPressed(Input.Key.RControl))
    Swag.require(not keyboard.isKeyPressed(Input.Key.LMenu))
    Swag.require(not keyboard.isKeyPressed(Input.Key.RMenu))
    Swag.require(keyboard.pressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.setKeyStates(.RShift, false, true)
    Swag.require(keyboard.pressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.setKeyStates(.LControl, false, true)
    Swag.require(keyboard.pressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.setKeyStates(.RControl, false, true)
    Swag.require(keyboard.pressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.setKeyStates(.LMenu, false, true)
    Swag.require(keyboard.pressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))

    keyboard.setKeyStates(.RMenu, false, true)
    Swag.require(keyboard.pressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))
}

#test
{
    var keyboard: Input.Keyboard

    for i in Input.Key.count
    {
        keyboard.setKeyStates(Input.keyFromStorageIndex(i), true, true)
        keyboard.isRepeating[i] = true
        keyboard.pressedAtMs[i] = cast(u32, i) + 1
    }

    keyboard.clear()

    for i in Input.Key.count
    {
        Swag.require(not keyboard.previousState.pressed[i])
        Swag.require(not keyboard.currentState.pressed[i])
        Swag.require(not keyboard.isRepeating[i])
        Swag.require(keyboard.pressedAtMs[i] == 0)
    }
}
