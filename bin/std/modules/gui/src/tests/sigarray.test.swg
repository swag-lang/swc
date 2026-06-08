#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

var SigArrayTestTotal: s32

func sigArrayTestAdd(value: *s32)
{
    discard value
    SigArrayTestTotal += 1
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
    signal.arr[0].fn(&value)
    signal.arr[1].fn(&value)
    @assert(SigArrayTestTotal == 11)

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
