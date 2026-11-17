#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var state: Type2State
    state.stack[0] = 2
    state.stack[1] = 0
    state.depth    = 2
    execType2Escape(&state, 3)
    Swag.require(state.depth == 1 and state.stack[0] == 0)

    state.stack[1] = 3
    state.depth    = 2
    execType2Escape(&state, 4)
    Swag.require(state.depth == 1 and state.stack[0] == 1)

    state.stack[0] = -2
    state.depth    = 1
    execType2Escape(&state, 5)
    Swag.require(state.depth == 1 and state.stack[0] == 0)

    state.stack[0] = 4
    state.stack[1] = 4
    state.depth    = 2
    execType2Escape(&state, 15)
    Swag.require(state.depth == 1 and state.stack[0] == 1)

    state.stack[0] = 9
    state.depth    = 1
    execType2Escape(&state, 3)
    Swag.require(state.depth == 1 and state.stack[0] == 9)
}

#test
{
    var state: Type2State
    state.stack[0] = 15
    state.stack[1] = 20
    state.stack[2] = 1
    state.stack[3] = 2
    state.depth    = 4
    execType2Escape(&state, 22)
    Swag.require(state.depth == 1 and state.stack[0] == 15)

    state.stack[0] = 20
    state.stack[1] = 15
    state.stack[2] = 2
    state.stack[3] = 1
    state.depth    = 4
    execType2Escape(&state, 22)
    Swag.require(state.depth == 1 and state.stack[0] == 15)

    state.stack[0] = 1
    state.stack[1] = 2
    state.stack[2] = 3
    state.depth    = 3
    execType2Escape(&state, 22)
    Swag.require(state.depth == 3)
}

#test
{
    var first:  Type2State
    var second: Type2State
    execType2Escape(&first, 23)
    execType2Escape(&second, 23)
    Swag.require(first.depth == 1 and second.depth == 1)
    Swag.require(first.stack[0] > 0 and first.stack[0] < 1)
    Swag.require(first.stack[0] == second.stack[0])
}

#test
{
    var state: Type2State
    state.stack[0] = 10
    state.stack[1] = 20
    state.stack[2] = 30
    state.stack[3] = 1
    state.depth    = 4
    execType2Escape(&state, 29)
    Swag.require(state.depth == 4 and state.stack[3] == 20)

    state.stack[3] = 20
    state.depth    = 4
    execType2Escape(&state, 29)
    Swag.require(state.depth == 4 and state.stack[3] == 10)

    state.stack[3] = -2
    state.depth    = 4
    execType2Escape(&state, 29)
    Swag.require(state.depth == 4 and state.stack[3] == 30)
}

#test
{
    var state: Type2State
    state.stack[0] = 1
    state.stack[1] = 2
    state.stack[2] = 3
    state.stack[3] = 3
    state.stack[4] = -1
    state.depth    = 5
    execType2Escape(&state, 30)
    Swag.require(state.depth == 3)
    Swag.require(state.stack[0] == 2 and state.stack[1] == 3 and state.stack[2] == 1)
}

#test
{
    const PlainCharstring: [8] u8 = ['3', ' ', 'R', 'D', ' ', 10, 20, 30]
    let entry = expect readCharstringData(PlainCharstring, 0, -1)
    Swag.require(entry.bytes.count == 3)
    Swag.require(entry.bytes[0] == 10 and entry.bytes[1] == 20 and entry.bytes[2] == 30)
    Swag.require(entry.next == PlainCharstring.count)
}
