#global private

var Calls: s32

struct Value
{
    number: s32
}

struct Box
{
    value: Value
}

#[Swag.NoInline]
func makeValue()->Value
{
    Calls += 1
    return {number: 42}
}

#[Swag.NoInline]
func makeBox()->Box
{
    return Box{value: makeValue()}
}

func callValue(callback: func()->Value)->Value
{
    return callback()
}

#test
{
    Calls = 0
    let box = makeBox()
    Swag.assert(box.value.number == 42)
    let value = (makeValue())
    Swag.assert(value.number == 42)
    let called = callValue(callback: &makeValue)
    Swag.assert(called.number == 42)
    let wrapped = Box{value: (makeValue())}
    Swag.assert(wrapped.value.number == 42)
    Swag.assert(Calls == 4)
}
