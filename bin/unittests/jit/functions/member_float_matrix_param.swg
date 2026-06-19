#global fileprivate

struct MemberFloatMatrixParamMatrix
{
    m: [4, 4] f32
}

struct MemberFloatMatrixParamHolder
{
    matrix: MemberFloatMatrixParamMatrix
}

func fillMemberFloatMatrix(b, t, l, r, n, f: f32, m: [4, 4] f32)
{
    m[0, 0] = 2 / (r - l)
    m[0, 1] = 0
    m[0, 2] = 0
    m[0, 3] = 0

    m[1, 0] = 0
    m[1, 1] = 2 / (t - b)
    m[1, 2] = 0
    m[1, 3] = 0

    m[2, 0] = 0
    m[2, 1] = 0
    m[2, 2] = -2 / (f - n)
    m[2, 3] = 0

    m[3, 0] = -(r + l) / (r - l)
    m[3, 1] = -(t + b) / (t - b)
    m[3, 2] = -(f + n) / (f - n)
    m[3, 3] = 1
}

#test
{
    var holder: MemberFloatMatrixParamHolder = undefined
    fillMemberFloatMatrix(10, 0, 0, 20, 0, 1, holder.matrix.m)
    @assert(holder.matrix.m[0, 0] == 0.1)
    @assert(holder.matrix.m[1, 1] == -0.2)
    @assert(holder.matrix.m[2, 2] == -2)
    @assert(holder.matrix.m[3, 0] == -1)
    @assert(holder.matrix.m[3, 1] == 1)
    @assert(holder.matrix.m[3, 2] == -1)
    @assert(holder.matrix.m[3, 3] == 1)
}
