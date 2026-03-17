// 

#global fileprivate

func sumValues(values: [..] s32)->s32
{
    var result = 0
    foreach value in values do
        result += value
    return result
}

#test
{
    var a: [2, 2] s32
    a[0, 0] = 1
    a[0, 1] = 2
    a[1, 0] = 3
    a[1, 1] = 4
    @assert(a[0, 0] + a[0, 1] + a[1, 0] + a[1, 1] == 10)

    var b: [2, 3, 4] s32
    b[1, 2, 3] = 42
    @assert(b[1, 2, 3] == 42)
    @assert(b[1][2][3] == 42)
}

#test
{
    var cube: [2, 2, 3] s32 = [
        [[1, 2, 3], [4, 5, 6]],
        [[7, 8, 9], [10, 11, 12]],
    ]

    #assert(#typeof(cube[0]) == #type [2, 3] s32)
    #assert(#typeof(cube[0, 1]) == #type [3] s32)
    #assert(#typeof(cube[0, 1, 2]) == s32)

    cube[0, 1, 1] = 50
    cube[1, 0, 2] += 10

    let ptr = &cube[1, 1, 2]
    @assert(dref ptr == 12)
    dref ptr = 77

    @assert(cube[0][1][1] == 50)
    @assert(cube[1][0][2] == 19)
    @assert(cube[1, 1, 0] == cube[1][1][0])
    @assert(cube[1, 1, 2] == 77)
    @assert(sumValues(cast([..] s32) cube[0, 1]) == 60)
    @assert(sumValues(cast([..] s32) cube[1][0]) == 34)
}

#test
{
    var grid: [3, 2] s32 = [[1, 2], [3, 4], [5, 6]]
    let top = grid[0]
    let middle = grid[1]

    grid[2, 0] = top[1] + middle[1]
    grid[2, 1] = top[0] + middle[0]

    @assert(grid[2, 0] == 6)
    @assert(grid[2, 1] == 4)
    @assert(sumValues(cast([..] s32) grid[2]) == 10)
}
