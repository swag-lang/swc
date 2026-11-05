#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var mouse: Input.Mouse

    for i in Input.MouseButton.count
    {
        let button = Input.mouseButtonFromStorageIndex(i)
        Swag.require(not mouse.isButtonPressed(button))
        Swag.require(mouse.isButtonReleased(button))
        Swag.require(not mouse.isButtonJustPressed(button))
        Swag.require(not mouse.isButtonJustReleased(button))
        Swag.require(not mouse.isButtonDoubleClick(button))
    }

    Swag.require(mouse.previousPosition() == Math.Point.Zero)
    Swag.require(mouse.position() == Math.Point.Zero)
    Swag.require(mouse.movement() == Math.Point.Zero)
}

#test
{
    var mouse: Input.Mouse

    for i in Input.MouseButton.count
    {
        let button = Input.mouseButtonFromStorageIndex(i)

        mouse.setButtonStates(button, false, true, true)

        Swag.require(mouse.isButtonPressed(button))
        Swag.require(not mouse.isButtonReleased(button))
        Swag.require(mouse.isButtonJustPressed(button))
        Swag.require(not mouse.isButtonJustReleased(button))
        Swag.require(mouse.isButtonDoubleClick(button))

        mouse.setButtonStates(button, true, true, true)

        Swag.require(mouse.isButtonPressed(button))
        Swag.require(not mouse.isButtonReleased(button))
        Swag.require(not mouse.isButtonJustPressed(button))
        Swag.require(not mouse.isButtonJustReleased(button))

        mouse.setButtonStates(button, true, false, false)

        Swag.require(not mouse.isButtonPressed(button))
        Swag.require(mouse.isButtonReleased(button))
        Swag.require(not mouse.isButtonJustPressed(button))
        Swag.require(mouse.isButtonJustReleased(button))
        Swag.require(not mouse.isButtonDoubleClick(button))
    }
}

#test
{
    var mouse: Input.Mouse

    mouse.setPositions({3, -4}, {10, 6})

    Swag.require(mouse.previousPosition() == Math.Point{3, -4})
    Swag.require(mouse.position() == Math.Point{10, 6})
    Swag.require(mouse.movement() == Math.Point{7, 10})
}

#test
{
    var mouse: Input.Mouse
    mouse.setButtonStates(.Left, true, true, true)
    mouse.setPressMetadata(.Left, 12, 34, {1, 2}, {3, 4})

    mouse.clear()

    Swag.require(not mouse.previousState.pressed[Input.MouseButton.Left])
    Swag.require(not mouse.currentState.pressed[Input.MouseButton.Left])
    Swag.require(mouse.previousState.pressedTime[Input.MouseButton.Left] == 0)
    Swag.require(mouse.currentState.pressedTime[Input.MouseButton.Left] == 0)
    Swag.require(mouse.previousState.pressedPos[Input.MouseButton.Left] == Math.Point.Zero)
    Swag.require(mouse.currentState.pressedPos[Input.MouseButton.Left] == Math.Point.Zero)
    Swag.require(not mouse.isButtonDoubleClick(.Left))
}
