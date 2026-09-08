#global private

func nestedParallelStack(depth: u64)->u64
{
    var location = 0'u64
    parallel for |&location, depth| index in 1
    {
        if depth == 0 do
            location = cast(u64) &location
        else do
            location = nestedParallelStack(depth - 1)
    }
    return location
}

// Seventeen serial partitions must not each reserve the full worker array. Address differences
// measure native stack use without dereferencing returned addresses or asserting a duration.
#test
{
    if Swag.jit() do
        return

    var marker   = 0'u64
    let anchor   = cast(u64) &marker
    let leaf     = nestedParallelStack(16)
    let distance = anchor > leaf ? anchor - leaf : leaf - anchor
    Swag.assert(distance < 64 * 1024)
}
