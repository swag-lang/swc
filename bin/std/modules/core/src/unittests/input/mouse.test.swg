#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var mouse: Input.Mouse

    for [i] in @countof(Input.MouseButton)
    {
        let button = cast(Input.MouseButton) i
        @assert(!mouse.isButtonPressed(button))
        @assert(mouse.isButtonReleased(button))
        @assert(!mouse.isButtonJustPressed(button))
        @assert(!mouse.isButtonJustReleased(button))
        @assert(!mouse.isButtonDoubleClick(button))
    }

    @assert(mouse.previousPosition() == Math.Point.Zero)
    @assert(mouse.position() == Math.Point.Zero)
    @assert(mouse.movement() == Math.Point.Zero)
}

#test
{
    var mouse: Input.Mouse

    for [i] in @countof(Input.MouseButton)
    {
        let button = cast(Input.MouseButton) i

        mouse.setButtonStates(button, false, true, true)

        @assert(mouse.isButtonPressed(button))
        @assert(!mouse.isButtonReleased(button))
        @assert(mouse.isButtonJustPressed(button))
        @assert(!mouse.isButtonJustReleased(button))
        @assert(mouse.isButtonDoubleClick(button))

        mouse.setButtonStates(button, true, true, true)

        @assert(mouse.isButtonPressed(button))
        @assert(!mouse.isButtonReleased(button))
        @assert(!mouse.isButtonJustPressed(button))
        @assert(!mouse.isButtonJustReleased(button))

        mouse.setButtonStates(button, true, false, false)

        @assert(!mouse.isButtonPressed(button))
        @assert(mouse.isButtonReleased(button))
        @assert(!mouse.isButtonJustPressed(button))
        @assert(mouse.isButtonJustReleased(button))
        @assert(!mouse.isButtonDoubleClick(button))
    }
}

#test
{
    var mouse: Input.Mouse

    mouse.setPositions({3, -4}, {10, 6})

    @assert(mouse.previousPosition() == Math.Point{3, -4})
    @assert(mouse.position() == Math.Point{10, 6})
    @assert(mouse.movement() == Math.Point{7, 10})
}

#test
{
    var mouse: Input.Mouse
    mouse.setButtonStates(.Left, true, true, true)
    mouse.setPressMetadata(.Left, 12, 34, {1, 2}, {3, 4})

    mouse.clear()

    @assert(!mouse.previousState.pressed[Input.MouseButton.Left])
    @assert(!mouse.currentState.pressed[Input.MouseButton.Left])
    @assert(mouse.previousState.pressedTime[Input.MouseButton.Left] == 0)
    @assert(mouse.currentState.pressedTime[Input.MouseButton.Left] == 0)
    @assert(mouse.previousState.pressedPos[Input.MouseButton.Left] == Math.Point.Zero)
    @assert(mouse.currentState.pressedPos[Input.MouseButton.Left] == Math.Point.Zero)
    @assert(!mouse.isButtonDoubleClick(.Left))
}
