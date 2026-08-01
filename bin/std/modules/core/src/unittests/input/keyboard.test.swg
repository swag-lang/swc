#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var keyboard: Input.Keyboard

    for [i] in @countof(Input.Key)
    {
        let key = cast(Input.Key) i
        @assert(!keyboard.isKeyPressed(key))
        @assert(keyboard.isKeyReleased(key))
        @assert(!keyboard.isKeyJustPressed(key))
        @assert(!keyboard.isKeyJustReleased(key))
    }
}

#test
{
    var keyboard: Input.Keyboard

    for [i] in @countof(Input.Key)
    {
        let key = cast(Input.Key) i

        keyboard.setKeyStates(key, false, true)

        @assert(keyboard.isKeyPressed(key))
        @assert(!keyboard.isKeyReleased(key))
        @assert(keyboard.isKeyJustPressed(key))
        @assert(!keyboard.isKeyJustReleased(key))

        keyboard.setKeyStates(key, true, true)

        @assert(keyboard.isKeyPressed(key))
        @assert(!keyboard.isKeyReleased(key))
        @assert(!keyboard.isKeyJustPressed(key))
        @assert(!keyboard.isKeyJustReleased(key))

        keyboard.setKeyStates(key, true, false)

        @assert(!keyboard.isKeyPressed(key))
        @assert(keyboard.isKeyReleased(key))
        @assert(!keyboard.isKeyJustPressed(key))
        @assert(keyboard.isKeyJustReleased(key))
    }
}

#test
{
    var keyboard: Input.Keyboard

    @assert(keyboard.pressedModifiers() == Input.KeyModifiers.None)

    keyboard.setKeyStates(.LShift, false, true)
    @assert(keyboard.isKeyPressed(Input.Key.LShift))
    @assert(!keyboard.isKeyPressed(Input.Key.RShift))
    @assert(!keyboard.isKeyPressed(Input.Key.LControl))
    @assert(!keyboard.isKeyPressed(Input.Key.RControl))
    @assert(!keyboard.isKeyPressed(Input.Key.LMenu))
    @assert(!keyboard.isKeyPressed(Input.Key.RMenu))
    @assert(keyboard.pressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.setKeyStates(.RShift, false, true)
    @assert(keyboard.pressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.setKeyStates(.LControl, false, true)
    @assert(keyboard.pressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.setKeyStates(.RControl, false, true)
    @assert(keyboard.pressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.setKeyStates(.LMenu, false, true)
    @assert(keyboard.pressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))

    keyboard.setKeyStates(.RMenu, false, true)
    @assert(keyboard.pressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))
}

#test
{
    var keyboard: Input.Keyboard

    for [i] in @countof(Input.Key)
    {
        keyboard.setKeyStates(cast(Input.Key) i, true, true)
        keyboard.isRepeating[i]           = true
        keyboard.pressedAtMs[i]           = cast(u32) i + 1
    }

    keyboard.clear()

    for [i] in @countof(Input.Key)
    {
        @assert(!keyboard.previousState.pressed[i])
        @assert(!keyboard.currentState.pressed[i])
        @assert(!keyboard.isRepeating[i])
        @assert(keyboard.pressedAtMs[i] == 0)
    }
}
