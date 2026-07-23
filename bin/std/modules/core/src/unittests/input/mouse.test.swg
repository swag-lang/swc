#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var mouse: Input.Mouse

    for i in @countof(Input.MouseButton)
    {
        let button = cast(Input.MouseButton) i
        @assert(!mouse.isButtonPressed(button))
        @assert(mouse.isButtonReleased(button))
        @assert(!mouse.isButtonJustPressed(button))
        @assert(!mouse.isButtonJustReleased(button))
        @assert(!mouse.isButtonDoubleClick(button))
    }

    @assert(mouse.getPreviousPos() == Math.Point.Zero)
    @assert(mouse.getPosition() == Math.Point.Zero)
    @assert(mouse.getMove() == Math.Point.Zero)
}

#test
{
    var mouse: Input.Mouse

    for i in @countof(Input.MouseButton)
    {
        let button = cast(Input.MouseButton) i

        mouse.currentState.pressed[button]  = true
        mouse.previousState.pressed[button] = false
        mouse.dblClk[button]                = true

        @assert(mouse.isButtonPressed(button))
        @assert(!mouse.isButtonReleased(button))
        @assert(mouse.isButtonJustPressed(button))
        @assert(!mouse.isButtonJustReleased(button))
        @assert(mouse.isButtonDoubleClick(button))

        mouse.previousState.pressed[button] = true

        @assert(mouse.isButtonPressed(button))
        @assert(!mouse.isButtonReleased(button))
        @assert(!mouse.isButtonJustPressed(button))
        @assert(!mouse.isButtonJustReleased(button))

        mouse.currentState.pressed[button] = false
        mouse.dblClk[button]               = false

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

    mouse.previousState.position = Math.Point{3, -4}
    mouse.currentState.position  = Math.Point{10, 6}

    @assert(mouse.getPreviousPos() == Math.Point{3, -4})
    @assert(mouse.getPosition() == Math.Point{10, 6})
    @assert(mouse.getMove() == Math.Point{7, 10})
}
