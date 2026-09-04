#global private
using Swag

func slicesEqual(lhs, rhs: const [..] s32?)->bool
{
    if lhs.count != rhs.count do
        return false
    if !lhs.count or !rhs.count do
        return true

    // A null slice has a zero count, so both slices are non-null past this point.
    if lhs == null or rhs == null do
        return true

    for i in lhs.count where lhs[i] != rhs[i] do
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
    Swag.assert(matchesLoop())
    Swag.assert(differsLoop())
}
