#global fileprivate

struct MemberExactArrayParamMatrix
{
    m: [2, 3] s16
}

struct MemberExactArrayParamHolder
{
    matrix: MemberExactArrayParamMatrix
}

func patchMemberExactMatrix(grid: [2, 3] s16, base: s16)
{
    grid[0, 1] = base
    grid[1, 0] = base + 1's16
    grid[1, 2] = base + 2's16
}

#test
{
    var holder = MemberExactArrayParamHolder{matrix: {m: [[1, 2, 3], [4, 5, 6]]}}
    patchMemberExactMatrix(holder.matrix.m, 20's16)
    @assert(holder.matrix.m[0, 0] == 1's16)
    @assert(holder.matrix.m[0, 1] == 20's16)
    @assert(holder.matrix.m[1, 0] == 21's16)
    @assert(holder.matrix.m[1, 2] == 22's16)
}
