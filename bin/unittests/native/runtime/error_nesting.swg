#global private

// Every level holds one error stack level of the context for as long as its 'catch' runs.
func nestedCatches(levels: u32)->u32 fail
{
    if levels == 0 do
        return 0
    return (catch nestedCatches(levels - 1) else 0) + 1
}

// Every level fails, so each one hands an error to the level that catches it.
func nestedFailures(levels: u32)->u32 fail
{
    if levels == 0 do
        fail Swag.BaseError{"deepest"}
    let below = catch nestedFailures(levels - 1) else 0
    if below == 0 do
        fail Swag.BaseError{"failed below"}
    return below
}

// The error stack grows with the nesting: deep recursion through 'catch' works and leaves the
// stack where it was.
#test
{
    let depth = Swag.getContext().errorIndex
    Swag.assert((catch nestedCatches(300) else 0) == 300)
    Swag.assert(Swag.getContext().errorIndex == depth)
}

// A failure at every level of a deep stack is caught by each level in turn.
#test
{
    let depth = Swag.getContext().errorIndex
    discard catch nestedFailures(100) as error
    Swag.assert(error != null)
    Swag.assert(Swag.getContext().errorIndex == depth)
}

// Only the first levels of the error stack live in the context, which keeps it small.
#assert(#sizeof(Swag.Context) <= 3040)
