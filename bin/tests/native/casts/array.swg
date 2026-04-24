#global fileprivate // 

#test
{
    var x: [2, 2] s32 = [[1, 2], [3, 4]]
    @assert(x[0, 0] == 1)
    @assert(x[0, 1] == 2)
    @assert(x[1, 0] == 3)
    @assert(x[1, 1] == 4)
}

#test
{
    const x: [2, 2] s32 = [[5, 6], [7, 8]]
    @assert(x[0, 0] == 5)
    @assert(x[0, 1] == 6)
    @assert(x[1, 0] == 7)
    @assert(x[1, 1] == 8)
}
