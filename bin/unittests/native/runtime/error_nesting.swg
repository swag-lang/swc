#global private

// Every level holds one error frame of the context for as long as its 'catch' runs.
func nestedCatches(levels: u32)->u32 fail
{
    if levels == 0 do
        return 0
    return (catch nestedCatches(levels - 1)) + 1
}

// The deepest call whose frames still fit, counted from the frames already in use.
func deepestFittingCall()->u32 => Swag.MaxErrors - 2 - Swag.getContext().errorIndex

func nestTooDeep(levels: u32)->Swag.CaughtPanic => Swag.catchPanic(func|levels|() { discard catch nestedCatches(levels) })

// Nesting up to the context's error stack works and leaves the stack where it was.
#test
{
    let depth  = Swag.getContext().errorIndex
    let levels = deepestFittingCall()
    Swag.assert((catch nestedCatches(levels)) == levels)
    Swag.assert(Swag.getContext().errorIndex == depth)
}

// One level more stops with the depth panic, at the limit and well past it, instead of reaching
// outside the stack.
#test
{
    let depth = Swag.getContext().errorIndex
    for levels in [deepestFittingCall() + 1, deepestFittingCall() + 10]
    {
        let caught = nestTooDeep(levels)
        Swag.assert(caught.raised)
        Swag.assert(caught.message() == "error propagation nesting exceeds its supported depth")
        Swag.assert(Swag.getContext().errorIndex == depth)
    }
}
