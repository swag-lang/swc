#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    var state: Input.KeyboardState

    for i in Input.Key.count
    {
        state.setPressed(Input.keyFromStorageIndex(i), true)
    }

    for i in Input.Key.count
    {
        Swag.require(state.pressed[i])
    }

    state.clear()

    for i in Input.Key.count
    {
        Swag.require(not state.pressed[i])
    }
}
