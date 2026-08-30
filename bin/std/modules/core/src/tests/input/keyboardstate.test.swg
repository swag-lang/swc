#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.KeyboardState

    for i in Input.Key.count do
        state.setPressed(cast(Input.Key) i, true)

    state.clear()

    for i in Input.Key.count do
        Swag.assert(!state.pressed[i])
}
