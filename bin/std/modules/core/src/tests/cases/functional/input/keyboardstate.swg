#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.KeyboardState

    for i in Input.Key.count do
        state.setPressed(Input.keyFromStorageIndex(i), true)

    state.clear()

    for i in Input.Key.count do
        Swag.require(not state.pressed[i])
}
