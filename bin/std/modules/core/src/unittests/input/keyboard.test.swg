#global #if #command == Swag.CompilerCommand.Test
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

        keyboard.currentState.pressed[key]  = true
        keyboard.previousState.pressed[key] = false

        @assert(keyboard.isKeyPressed(key))
        @assert(!keyboard.isKeyReleased(key))
        @assert(keyboard.isKeyJustPressed(key))
        @assert(!keyboard.isKeyJustReleased(key))

        keyboard.previousState.pressed[key] = true

        @assert(keyboard.isKeyPressed(key))
        @assert(!keyboard.isKeyReleased(key))
        @assert(!keyboard.isKeyJustPressed(key))
        @assert(!keyboard.isKeyJustReleased(key))

        keyboard.currentState.pressed[key] = false

        @assert(!keyboard.isKeyPressed(key))
        @assert(keyboard.isKeyReleased(key))
        @assert(!keyboard.isKeyJustPressed(key))
        @assert(keyboard.isKeyJustReleased(key))
    }
}

#test
{
    var keyboard: Input.Keyboard

    @assert(keyboard.getPressedModifiers() == Input.KeyModifiers.Zero)

    keyboard.currentState.pressed[Input.Key.LShift] = true
    @assert(keyboard.isKeyPressed(Input.Key.LShift))
    @assert(!keyboard.isKeyPressed(Input.Key.RShift))
    @assert(!keyboard.isKeyPressed(Input.Key.LControl))
    @assert(!keyboard.isKeyPressed(Input.Key.RControl))
    @assert(!keyboard.isKeyPressed(Input.Key.LMenu))
    @assert(!keyboard.isKeyPressed(Input.Key.RMenu))
    @assert(keyboard.getPressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.currentState.pressed[Input.Key.RShift] = true
    @assert(keyboard.getPressedModifiers() == Input.KeyModifiers.Shift)

    keyboard.currentState.pressed[Input.Key.LControl] = true
    @assert(keyboard.getPressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.currentState.pressed[Input.Key.RControl] = true
    @assert(keyboard.getPressedModifiers() == Input.KeyModifiers.CtrlShift)

    keyboard.currentState.pressed[Input.Key.LMenu] = true
    @assert(keyboard.getPressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))

    keyboard.currentState.pressed[Input.Key.RMenu] = true
    @assert(keyboard.getPressedModifiers() == (Input.KeyModifiers.CtrlShift | Input.KeyModifiers.Alt))
}

#test
{
    var keyboard: Input.Keyboard

    for [i] in @countof(Input.Key)
    {
        keyboard.previousState.pressed[i] = true
        keyboard.currentState.pressed[i]  = true
        keyboard.pressedRepeat[i]         = true
        keyboard.pressedTime[i]           = cast(u32) i + 1
    }

    keyboard.clear()

    for [i] in @countof(Input.Key)
    {
        @assert(!keyboard.previousState.pressed[i])
        @assert(!keyboard.currentState.pressed[i])
        @assert(!keyboard.pressedRepeat[i])
        @assert(keyboard.pressedTime[i] == 0)
    }
}
