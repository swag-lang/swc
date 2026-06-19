#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

var SigArrayTestTotal: s32
var SigArrayTestTrace: String

func sigArrayTestAdd(value: *s32)
{
    discard value
    SigArrayTestTotal += 1
}

func sigArrayTestAddDelta(value: *s32, delta: s32)
{
    discard value
    SigArrayTestTotal += delta
}

func sigArrayTestAppendA(value: *s32)
{
    dref value += 1
    SigArrayTestTrace += "A"
}

#test
{
    var signal: SigArray'func||(*s32)
    @assert(signal.isEmpty())

    signal += &sigArrayTestAdd
    signal += func(value: *s32) { discard value; SigArrayTestTotal += 10 }
    @assert(!signal.isEmpty())
    @assert(signal.arr.count == 2)

    var value = 3
    SigArrayTestTotal = 0
    signal.call(&value)
    @assert(SigArrayTestTotal == 11)

    signal.disable()
    signal.disable()
    @assert(signal.disabled == 2)
    signal.call(&value)
    @assert(SigArrayTestTotal == 11)

    signal.enable()
    @assert(signal.disabled == 1)

    signal.enable()
    @assert(signal.disabled == 0)
    value = 4
    signal.call(&value)
    @assert(SigArrayTestTotal == 22)
}

#test
{
    var signal: SigArray'func||(*s32, s32)
    signal += &sigArrayTestAddDelta
    signal += func(value: *s32, delta: s32)
    {
        discard value
        SigArrayTestTotal += delta * 10
    }

    var value = 5
    SigArrayTestTotal = 0
    signal.call(&value, 3)
    @assert(SigArrayTestTotal == 33)
}

#test
{
    var signal: SigArray'func||(*s32)
    signal += &sigArrayTestAppendA
    signal += func(value: *s32)
    {
        dref value *= 3
        SigArrayTestTrace += "B"
    }
    signal += func(value: *s32)
    {
        dref value -= 2
        SigArrayTestTrace += "C"
    }

    var value = 4
    SigArrayTestTrace.clear()
    signal.call(&value)

    @assert(value == 13)
    @assert(SigArrayTestTrace == "ABC")
}
