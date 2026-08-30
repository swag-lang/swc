#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var mouse: Input.Mouse

    for i in Input.MouseButton.count
    {
        let button = cast(Input.MouseButton) i
        Swag.assert(!mouse.isButtonPressed(button))
        Swag.assert(mouse.isButtonReleased(button))
        Swag.assert(!mouse.isButtonJustPressed(button))
        Swag.assert(!mouse.isButtonJustReleased(button))
        Swag.assert(!mouse.isButtonDoubleClick(button))
    }

    Swag.assert(mouse.previousPosition() == Math.Point.Zero)
    Swag.assert(mouse.position() == Math.Point.Zero)
    Swag.assert(mouse.movement() == Math.Point.Zero)
}

#test
{
    var mouse: Input.Mouse

    for i in Input.MouseButton.count
    {
        let button = cast(Input.MouseButton) i

        mouse.setButtonStates(button, false, true, true)

        Swag.assert(mouse.isButtonPressed(button))
        Swag.assert(!mouse.isButtonReleased(button))
        Swag.assert(mouse.isButtonJustPressed(button))
        Swag.assert(!mouse.isButtonJustReleased(button))
        Swag.assert(mouse.isButtonDoubleClick(button))

        mouse.setButtonStates(button, true, true, true)

        Swag.assert(mouse.isButtonPressed(button))
        Swag.assert(!mouse.isButtonReleased(button))
        Swag.assert(!mouse.isButtonJustPressed(button))
        Swag.assert(!mouse.isButtonJustReleased(button))

        mouse.setButtonStates(button, true, false, false)

        Swag.assert(!mouse.isButtonPressed(button))
        Swag.assert(mouse.isButtonReleased(button))
        Swag.assert(!mouse.isButtonJustPressed(button))
        Swag.assert(mouse.isButtonJustReleased(button))
        Swag.assert(!mouse.isButtonDoubleClick(button))
    }
}

#test
{
    var mouse: Input.Mouse

    mouse.setPositions({3, -4}, {10, 6})

    Swag.assert(mouse.previousPosition() == Math.Point{3, -4})
    Swag.assert(mouse.position() == Math.Point{10, 6})
    Swag.assert(mouse.movement() == Math.Point{7, 10})
}

#test
{
    var mouse: Input.Mouse
    mouse.setButtonStates(.Left, true, true, true)
    mouse.setPressMetadata(.Left, 12, 34, {1, 2}, {3, 4})

    mouse.clear()

    Swag.assert(!mouse.previousState.pressed[Input.MouseButton.Left])
    Swag.assert(!mouse.currentState.pressed[Input.MouseButton.Left])
    Swag.assert(mouse.previousState.pressedTime[Input.MouseButton.Left] == 0)
    Swag.assert(mouse.currentState.pressedTime[Input.MouseButton.Left] == 0)
    Swag.assert(mouse.previousState.pressedPos[Input.MouseButton.Left] == Math.Point.Zero)
    Swag.assert(mouse.currentState.pressedPos[Input.MouseButton.Left] == Math.Point.Zero)
    Swag.assert(!mouse.isButtonDoubleClick(.Left))
}
