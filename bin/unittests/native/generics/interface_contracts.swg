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
    where T is IValue
{
    let view = value as IValue
    return view.value()
}

func(T) readAndReset(value: *T)->s32
    where T is IValue and T is IReset
{
    let view     = value as IValue
    let result   = view.value()
    let resetter = value as IReset
    resetter.reset()
    return result
}

func(T) classify(value: T)->s32 where T is IValue    => 1
func(T) classify(value: T)->s32 where !(T is IValue) => 2

struct(T) Holder where T is IValue
{
    value: T
}

#test
{
    #assert(Counter is IValue)
    #assert(CounterAlias is ValueAlias)
    #assert(Wrapper is IValue)
    #assert(IValue is IValue)
    #assert(!(IReset is IValue))
    #assert(!(Missing is IValue))
    #assert(!(s32 is IValue))
    #assert(!((#type *Counter) is IValue))

    var value = Counter{42}
    Swag.assert(readValue(&value) == 42)
    Swag.assert(readValue'Counter(&value) == 42)
    Swag.assert(classify(value) == 1)
    Swag.assert(classify(Missing{}) == 2)

    let direct   = value as IValue
    let pointer  = (&value) as IValue
    let explicit = cast(IValue) &value
    Swag.assert(direct.value() == explicit.value())
    Swag.assert(pointer.value() == explicit.value())
    #assert(#typeof(pointer) == IValue)

    var wrapper = Wrapper{prefix: 10, counter: {21}}
    let wrapped = (&wrapper) as ValueAlias
    Swag.assert(wrapped.value() == 21)
    Swag.assert(readValue(&wrapper) == 21)
    Swag.assert(readAndReset(&wrapper) == 21)
    Swag.assert(wrapper.count == 0)

    var holder: Holder'Counter = {value: {12}}
    Swag.assert(readValue(&holder.value) == 12)

    let same = pointer as IValue
    Swag.assert(same.value() == 42)
    let concrete = pointer as Counter
    Swag.assert(concrete!.count == 42)
    Swag.assert(pointer is Counter)
}
