#global private

// A local function is visible from its declaration on, so a sibling it calls is analyzed
// before the call is met and the call is a plain candidate.
func runLocal(count: u32)->u32
{
    func second(start: u32)->u32 => start * 2

    func first(start: u32)->u32 => second(start) + 1

    return first(count)
}

// Expanded in a function that only runs natively: a '#test' body is also compiled for the
// compile-time engine, where the automatic candidates that meet the forward call are not picked.
func runMacro(count: u32)->u32
{
    var sum = 0'u32
    InlineLocalForwardCall.visitTwice(count, &sum) #code(index, data)
    {
        let total = cast(*u32) data!
        total[] += index
    }
    return sum
}

#test
{
    Swag.assert(runLocal(20) == 41)
    Swag.assert(runMacro(3) == 0 + 1 + 2 + 3 + 4 + 5)
}
