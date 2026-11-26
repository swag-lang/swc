#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var state: Type2State
    state.stack[0] = 2
    state.stack[1] = 0
    state.depth    = 2
    expect execType2Escape(&state, 3)
    Swag.require(state.depth == 1 and state.stack[0] == 0)

    state.stack[1] = 3
    state.depth    = 2
    expect execType2Escape(&state, 4)
    Swag.require(state.depth == 1 and state.stack[0] == 1)

    state.stack[0] = -2
    state.depth    = 1
    expect execType2Escape(&state, 5)
    Swag.require(state.depth == 1 and state.stack[0] == 0)

    state.stack[0] = 4
    state.stack[1] = 4
    state.depth    = 2
    expect execType2Escape(&state, 15)
    Swag.require(state.depth == 1 and state.stack[0] == 1)

    state.stack[0] = 9
    state.depth    = 1
    expect execType2Escape(&state, 3)
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
    expect execType2Escape(&state, 22)
    Swag.require(state.depth == 1 and state.stack[0] == 15)

    state.stack[0] = 20
    state.stack[1] = 15
    state.stack[2] = 2
    state.stack[3] = 1
    state.depth    = 4
    expect execType2Escape(&state, 22)
    Swag.require(state.depth == 1 and state.stack[0] == 15)

    state.stack[0] = 1
    state.stack[1] = 2
    state.stack[2] = 3
    state.depth    = 3
    expect execType2Escape(&state, 22)
    Swag.require(state.depth == 3)
}

#test
{
    var first:  Type2State
    var second: Type2State
    expect execType2Escape(&first, 23)
    expect execType2Escape(&second, 23)
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
    expect execType2Escape(&state, 29)
    Swag.require(state.depth == 4 and state.stack[3] == 20)

    state.stack[3] = 20
    state.depth    = 4
    expect execType2Escape(&state, 29)
    Swag.require(state.depth == 4 and state.stack[3] == 10)

    state.stack[3] = -2
    state.depth    = 4
    expect execType2Escape(&state, 29)
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
    expect execType2Escape(&state, 30)
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

// Type 2 and Type 1 reject operands beyond their bounded charstring stacks.
#test
{
    var code: Array'u8
    for MaxCharstringStack + 1 do
        code.add(32)

    var indexBytes: Array'u8
    indexBytes.add([0, 1, 1, 1, cast(u8, code.count + 1)])
    indexBytes.add(code.toSlice())
    var type2: CffFont
    type2.block       = indexBytes.toSlice()
    type2.charStrings = expect readCffIndex(type2.block, 0)
    var type2Outcome: Swag.Error
    discard catch runType2Charstring(&type2, 0, null) as type2Outcome
    Swag.require(type2Outcome.value() != null)

    var type1: Type1Font
    type1.charstrings.add(code)
    var type1Outcome: Swag.Error
    discard catch runType1Charstring(&type1, 0, null) as type1Outcome
    Swag.require(type1Outcome.value() != null)
}

// Escaped operators that push also reject overflow instead of silently changing the program.
#test
{
    var state: Type2State
    state.depth = MaxCharstringStack

    var duplicateOutcome: Swag.Error
    discard catch execType2Escape(&state, 27) as duplicateOutcome
    Swag.require(duplicateOutcome.value() != null)

    state.depth = MaxCharstringStack
    var randomOutcome: Swag.Error
    discard catch execType2Escape(&state, 23) as randomOutcome
    Swag.require(randomOutcome.value() != null)
}

// Type 1 OtherSubr retains the full set of values it returns to the charstring stack.
#test
{
    var charstring: Array'u8
    charstring.add(139)     // zero side bearing
    charstring.add(139)     // zero advance
    charstring.add(13)      // hsbw
    for index in 33 do
        charstring.add(cast(u8, index + 140))
    charstring.add(172)     // OtherSubr argument count 33
    charstring.add(142)     // OtherSubr 3, which returns its arguments unchanged
    charstring.add(12)
    charstring.add(16)     // callothersubr
    charstring.add(12)
    charstring.add(17)     // pop the first returned value
    charstring.add(12)
    charstring.add(17)     // pop the second returned value
    charstring.add(12)
    charstring.add(33)     // setcurrentpoint
    charstring.add(139)
    charstring.add(139)
    charstring.add(21)     // rmoveto
    charstring.add(140)
    charstring.add(139)
    charstring.add(5)      // rlineto
    charstring.add(14)     // endchar

    var font: Type1Font
    font.charstrings.add(charstring)

    var face: FaceImpl
    var builder = OutlineBuilder.create(&face, 1000, 1000, 1000)
    discard expect runType1Charstring(&font, 0, &builder)

    Swag.require(face.outlinePoints.count == 2)
    Swag.require(face.outlinePoints[0].x == 64 and face.outlinePoints[0].y == 128)
}
