#global private

#[Swag.NoReturn]
func stopWith(message: string)
{
    Swag.panic(message, #curlocation)
}

// A panic raised inside the call is caught with its message, and the hook in place before the
// call is back afterwards.
#test
{
    let before = Swag.getContext().panic
    let caught = Swag.catchPanic(func() { stopWith("inner stop") })
    Swag.assert(caught.raised)
    Swag.assert(caught.message() == "inner stop")
    Swag.assert(Swag.getContext().panic == before)
}

// A call that returns reports nothing.
#test
{
    var ran    = false
    let caught = Swag.catchPanic(func|&ran|() { ran = true })
    Swag.assert(ran)
    Swag.assert(not caught.raised and caught.message() == "")
}

// Catches nest: the inner one takes the panic, and the outer one sees its call return.
#test
{
    var innerRaised = false
    let outer       = Swag.catchPanic(func|&innerRaised|() { innerRaised = Swag.catchPanic(func() { stopWith("nested") }).raised })
    Swag.assert(innerRaised)
    Swag.assert(not outer.raised)
}

// A message longer than the report keeps is cut, not overflowed.
#test
{
    var long: [300] u8
    for i in long.count do
        long[i] = 'x'
    let message = Swag.makeString(&long[0], long.count)
    let caught  = Swag.catchPanic(func|message|() { stopWith(message) })
    Swag.assert(caught.raised and caught.message().count == 256)
}
