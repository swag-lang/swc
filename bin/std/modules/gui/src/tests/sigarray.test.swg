#global if #command == Swag.CompilerCommand.Test
#global private

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
    value[]           += 1
    SigArrayTestTrace += "A"
}

#test
{
    var signal: SigArray'func||(*s32)
    Swag.assert(signal.isEmpty())

    signal += &sigArrayTestAdd
    signal += func(value: *s32) { discard value; SigArrayTestTotal += 10 }
    Swag.assert(!signal.isEmpty())
    Swag.assert(signal.count() == 2)

    var value = 3
    SigArrayTestTotal = 0
    signal.call(&value)
    Swag.assert(SigArrayTestTotal == 11)

    signal.disable()
    signal.disable()
    Swag.assert(signal.isDisabled())
    signal.call(&value)
    Swag.assert(SigArrayTestTotal == 11)

    signal.enable()
    Swag.assert(signal.isDisabled())

    signal.enable()
    Swag.assert(!signal.isDisabled())
    value = 4
    signal.call(&value)
    Swag.assert(SigArrayTestTotal == 22)

    signal.clear()
    Swag.assert(signal.isEmpty())
    Swag.assert(!signal.isDisabled())
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
    Swag.assert(SigArrayTestTotal == 33)
}

#test
{
    var signal: SigArray'func||(*s32)
    signal += &sigArrayTestAppendA
    signal += func(value: *s32)
    {
        value[]           *= 3
        SigArrayTestTrace += "B"
    }
    signal += func(value: *s32)
    {
        value[]           -= 2
        SigArrayTestTrace += "C"
    }

    var value = 4
    SigArrayTestTrace.clear()
    signal.call(&value)

    Swag.assert(value == 13)
    Swag.assert(SigArrayTestTrace == "ABC")
}
