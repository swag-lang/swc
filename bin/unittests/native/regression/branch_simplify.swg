#global fileprivate

#[Swag.Optimize(true)]
func branchSimplifyKnownTrue()->s32
{
    var value = 0
    if value == 0 do
        return 11

    return 22
}

#[Swag.Optimize(true)]
func branchSimplifyKnownFalse()->s32
{
    var value = 5
    if value == 0 do
        return 11

    return 22
}

#[Swag.Optimize(true)]
func branchSimplifyLoop()->s32
{
    var total = 0
    var i = 0
    while i < 8
    {
        defer i += 1

        if i == 2 do
            continue
        if i == 6 do
            break

        total += i
    }

    return total
}

#test
{
    @assert(branchSimplifyKnownTrue() == 11)
    @assert(branchSimplifyKnownFalse() == 22)
    @assert(branchSimplifyLoop() == 13)
}
