#global private
using Swag

func slicesEqual(lhs, rhs: #null const [..] s32)->bool
{
    if @countof(lhs) != @countof(rhs) do
        return false
    if !@countof(lhs) or !@countof(rhs) do
        return true

    for i in lhs where lhs[i] != rhs[i] do
        return false
    return true
}

func matchesLoop()->bool
{
    let lhs: [3] s32 = [1, 2, 3]
    let rhs: [3] s32 = [1, 2, 3]
    return slicesEqual(lhs, rhs)
}

func differsLoop()->bool
{
    let lhs: [3] s32 = [1, 2, 3]
    let rhs: [3] s32 = [1, 9, 3]
    return !slicesEqual(lhs, rhs)
}

#test
{
    @assert(matchesLoop())
    @assert(differsLoop())
}
