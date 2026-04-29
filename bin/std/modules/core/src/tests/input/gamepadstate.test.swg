#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var state: Input.GamePadState

    for i in @countof(Input.GamePadButton)
    {
        let button = cast(Input.GamePadButton) i
        state.pressed[button]  = true
        state.position[button] = Math.Point{cast(f32) i + 0.25, cast(f32) i + 0.75}
    }

    state.clear()

    for i in @countof(Input.GamePadButton)
    {
        let button = cast(Input.GamePadButton) i
        @assert(!state.pressed[button])
        @assert(state.position[button] == Math.Point.Zero)
    }
}
