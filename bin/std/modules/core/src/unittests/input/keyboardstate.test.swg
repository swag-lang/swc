#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.KeyboardState

    for i in @countof(Input.Key) do
        state.pressed[i] = true

    state.clear()

    for i in @countof(Input.Key) do
        @assert(!state.pressed[i])
}
