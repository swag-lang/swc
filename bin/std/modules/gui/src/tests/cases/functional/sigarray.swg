#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var SigArrayTestTotal: s32
var SigArrayTestTrace: String

// A callback without arguments has no reflected parameter slice.
#test
{
    var signal: SigArray'func||()
    SigArrayTestTotal = 0
    signal += func() { SigArrayTestTotal += 1 }
    signal.call()
    Swag.require(SigArrayTestTotal == 1)
    signal.disable()
    signal.call()
    Swag.require(SigArrayTestTotal == 1)
    signal.enable()
    signal.call()
    Swag.require(SigArrayTestTotal == 2)
}

func sigArrayTestAdd(_: *s32)
{
    SigArrayTestTotal += 1
}

func sigArrayTestAddDelta(_: *s32, delta: s32)
{
    SigArrayTestTotal += delta
}

func sigArrayTestAppendA(value: *s32)
{
    value[] += 1
    SigArrayTestTrace += "A"
}

// A signal calls every registered callback, and disabling nests: each `disable` needs its own `enable`.
#test
{
    var signal: SigArray'func||(*s32)
    Swag.require(signal.isEmpty())

    signal += &sigArrayTestAdd
    signal += func(_: *s32) { SigArrayTestTotal += 10 }
    Swag.require(not signal.isEmpty())
    Swag.require(signal.count() == 2)

    var value = 3
    SigArrayTestTotal = 0
    signal.call(&value)
    Swag.require(SigArrayTestTotal == 11)

    signal.disable()
    signal.disable()
    Swag.require(signal.isDisabled())
    signal.call(&value)
    Swag.require(SigArrayTestTotal == 11)

    signal.enable()
    Swag.require(signal.isDisabled())

    signal.enable()
    Swag.require(not signal.isDisabled())
    value = 4
    signal.call(&value)
    Swag.require(SigArrayTestTotal == 22)

    signal.clear()
    Swag.require(signal.isEmpty())
    Swag.require(not signal.isDisabled())
}

// A callback with several parameters receives every argument.
#test
{
    var signal: SigArray'func||(*s32, s32)
    signal += &sigArrayTestAddDelta
    signal += func(_: *s32, delta: s32)
    {
        SigArrayTestTotal += delta * 10
    }

    var value = 5
    SigArrayTestTotal = 0
    signal.call(&value, 3)
    Swag.require(SigArrayTestTotal == 33)
}

// Callbacks run in registration order, each one seeing what the previous one wrote.
#test
{
    var signal: SigArray'func||(*s32)
    signal += &sigArrayTestAppendA
    signal += func(value: *s32)
    {
        value[] *= 3
        SigArrayTestTrace += "B"
    }

    signal += func(value: *s32)
    {
        value[] -= 2
        SigArrayTestTrace += "C"
    }

    var value = 4
    SigArrayTestTrace.clear()
    signal.call(&value)

    Swag.require(value == 13)
    Swag.require(SigArrayTestTrace == "ABC")
}
