#test
{
    let values = [[1, 2], [3, 4.0]]

    #assert(#typeof(values[1][0]) == #typeof(values[1, 0]))
    @assert(values[1, 0] == values[1][0])
    @assert(values[1, 1] == 4.0)
}
