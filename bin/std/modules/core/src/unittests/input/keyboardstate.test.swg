#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.KeyboardState

    for [i] in @countof(Input.Key) do
        state.setPressed(cast(Input.Key) i, true)

    state.clear()

    for [i] in @countof(Input.Key) do
        @assert(!state.pressed[i])
}
