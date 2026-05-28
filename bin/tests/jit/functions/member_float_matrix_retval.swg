#global fileprivate

struct MemberFloatMatrixRetval
{
    m: [4, 4] f32
}

struct MemberFloatMatrixRetvalHolder
{
    matrix: MemberFloatMatrixRetval
}

func buildMemberFloatMatrix(b, t, l, r, n, f: f32)->MemberFloatMatrixRetval
{
    var result: retval
    result.m[0, 0] = 2 / (r - l)
    result.m[0, 1] = 0
    result.m[0, 2] = 0
    result.m[0, 3] = 0

    result.m[1, 0] = 0
    result.m[1, 1] = 2 / (t - b)
    result.m[1, 2] = 0
    result.m[1, 3] = 0

    result.m[2, 0] = 0
    result.m[2, 1] = 0
    result.m[2, 2] = -2 / (f - n)
    result.m[2, 3] = 0

    result.m[3, 0] = -(r + l) / (r - l)
    result.m[3, 1] = -(t + b) / (t - b)
    result.m[3, 2] = -(f + n) / (f - n)
    result.m[3, 3] = 1
    return result
}

#test
{
    const ok = #run
    {
        var holder: MemberFloatMatrixRetvalHolder = undefined
        holder.matrix = buildMemberFloatMatrix(10, 0, 0, 20, 0, 1)
        return holder.matrix.m[0, 0] == 0.1 and
               holder.matrix.m[1, 1] == -0.2 and
               holder.matrix.m[2, 2] == -2 and
               holder.matrix.m[3, 0] == -1 and
               holder.matrix.m[3, 1] == 1 and
               holder.matrix.m[3, 2] == -1 and
               holder.matrix.m[3, 3] == 1
    }
    #assert(ok)
}
