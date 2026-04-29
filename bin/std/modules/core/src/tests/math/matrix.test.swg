#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

#test
{
    var matrix: Math.Matrix3x3 = undefined
    for y in 3
    {
        for x in 3 do
            matrix.m[x, y] = 7
    }

    matrix.setIdentity()

    @assert(matrix.m[0, 0] == 1)
    @assert(matrix.m[0, 1] == 0)
    @assert(matrix.m[0, 2] == 0)
    @assert(matrix.m[1, 0] == 0)
    @assert(matrix.m[1, 1] == 1)
    @assert(matrix.m[1, 2] == 0)
    @assert(matrix.m[2, 0] == 0)
    @assert(matrix.m[2, 1] == 0)
    @assert(matrix.m[2, 2] == 1)
}

#test
{
    var matrix: Math.Matrix4x4 = undefined
    for y in 4
    {
        for x in 4 do
            matrix.m[x, y] = 7
    }

    matrix.setIdentity()

    @assert(matrix.m[0, 0] == 1)
    @assert(matrix.m[0, 1] == 0)
    @assert(matrix.m[0, 2] == 0)
    @assert(matrix.m[0, 3] == 0)
    @assert(matrix.m[1, 0] == 0)
    @assert(matrix.m[1, 1] == 1)
    @assert(matrix.m[1, 2] == 0)
    @assert(matrix.m[1, 3] == 0)
    @assert(matrix.m[2, 0] == 0)
    @assert(matrix.m[2, 1] == 0)
    @assert(matrix.m[2, 2] == 1)
    @assert(matrix.m[2, 3] == 0)
    @assert(matrix.m[3, 0] == 0)
    @assert(matrix.m[3, 1] == 0)
    @assert(matrix.m[3, 2] == 0)
    @assert(matrix.m[3, 3] == 1)
}
