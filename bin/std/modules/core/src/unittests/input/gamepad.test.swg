#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var pad: Input.GamePad

    for [i] in @countof(Input.GamePadButton)
    {
        let button = cast(Input.GamePadButton) i
        @assert(!pad.isButtonPressed(button))
        @assert(pad.isButtonReleased(button))
        @assert(!pad.isButtonJustPressed(button))
        @assert(!pad.isButtonJustReleased(button))
        @assert(pad.getPosition(button) == Math.Point.Zero)
    }
}

#test
{
    var pad: Input.GamePad

    for [i] in @countof(Input.GamePadButton)
    {
        let button = cast(Input.GamePadButton) i
        let pos    = Math.Point{cast(f32) i + 1.0, cast(f32) i + 2.0}

        pad.currentState.pressed[button]  = true
        pad.previousState.pressed[button] = false
        pad.currentState.position[button] = pos

        @assert(pad.isButtonPressed(button))
        @assert(!pad.isButtonReleased(button))
        @assert(pad.isButtonJustPressed(button))
        @assert(!pad.isButtonJustReleased(button))
        @assert(pad.getPosition(button) == pos)

        pad.previousState.pressed[button] = true
        @assert(pad.isButtonPressed(button))
        @assert(!pad.isButtonReleased(button))
        @assert(!pad.isButtonJustPressed(button))
        @assert(!pad.isButtonJustReleased(button))

        pad.currentState.pressed[button] = false
        @assert(!pad.isButtonPressed(button))
        @assert(pad.isButtonReleased(button))
        @assert(!pad.isButtonJustPressed(button))
        @assert(pad.isButtonJustReleased(button))
    }
}

#test
{
    var pad: Input.GamePad

    for [i] in @countof(Input.GamePadButton)
    {
        let button = cast(Input.GamePadButton) i
        pad.previousState.pressed[button]  = true
        pad.currentState.pressed[button]   = true
        pad.previousState.position[button] = Math.Point{1, 2}
        pad.currentState.position[button]  = Math.Point{3, 4}
    }

    pad.clear()

    for [i] in @countof(Input.GamePadButton)
    {
        let button = cast(Input.GamePadButton) i
        @assert(!pad.previousState.pressed[button])
        @assert(!pad.currentState.pressed[button])
        @assert(pad.previousState.position[button] == Math.Point.Zero)
        @assert(pad.currentState.position[button] == Math.Point.Zero)
    }
}
