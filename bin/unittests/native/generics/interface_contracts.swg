#global private

interface IValue
{
    mtd value()->s32
}

interface IReset
{
    mtd reset()
}

struct Counter
{
    count: s32
}

impl IValue for Counter
{
    mtd value()->s32 => .count
}

impl IReset for Counter
{
    mtd reset() { .count = 0 }
}

struct Wrapper
{
    prefix:        s64
    using counter: Counter
}

struct Missing {}

alias CounterAlias = Counter
alias ValueAlias   = IValue

func(T) readValue(value: *T)->s32
    where (cast #try (IValue) T != null)
{
    let view = cast(IValue) value
    return view.value()
}

func(T) readAndReset(value: *T)->s32
    where (cast #try (IValue) T != null) and (cast #try (IReset) T != null)
{
    let view     = cast(IValue) value
    let result   = view.value()
    let resetter = cast(IReset) value
    resetter.reset()
    return result
}

func(T) classify(value: T)->s32 where (cast #try (IValue) T != null)       => 1
func(T) classify(value: T)->s32 where not ((cast #try (IValue) T != null)) => 2

struct(T) Holder where (cast #try (IValue) T != null)
{
    value: T
}

#test
{
    #assert((cast #try (IValue) Counter != null))
    #assert((cast #try (ValueAlias) CounterAlias != null))
    #assert((cast #try (IValue) Wrapper != null))
    #assert((cast #try (IValue) IValue != null))
    #assert(not ((cast #try (IValue) IReset != null)))
    #assert(not ((cast #try (IValue) Missing != null)))
    #assert(not ((cast #try (IValue) s32 != null)))
    #assert(cast #try (IValue) (#type *Counter) != null)

    var value = Counter{42}
    Swag.assert(readValue(&value) == 42)
    Swag.assert(readValue'Counter(&value) == 42)
    Swag.assert(classify(value) == 1)
    Swag.assert(classify(Missing{}) == 2)

    let direct   = cast(IValue) value
    let pointer  = cast(IValue) &value
    let explicit = cast(IValue) &value
    Swag.assert(direct.value() == explicit.value())
    Swag.assert(pointer.value() == explicit.value())
    #assert(#typeof(pointer) == IValue)

    var wrapper = Wrapper{prefix: 10, counter: {21}}
    let wrapped = cast(ValueAlias) &wrapper
    Swag.assert(wrapped.value() == 21)
    Swag.assert(readValue(&wrapper) == 21)
    Swag.assert(readAndReset(&wrapper) == 21)
    Swag.assert(wrapper.count == 0)

    var holder: Holder'Counter = {value: {12}}
    Swag.assert(readValue(&holder.value) == 12)

    let same = cast(IValue) pointer
    Swag.assert(same.value() == 42)
    let concrete = cast #try (*Counter) pointer
    Swag.assert(concrete!.count == 42)
    Swag.assert((cast #try (*Counter) pointer != null))
}
