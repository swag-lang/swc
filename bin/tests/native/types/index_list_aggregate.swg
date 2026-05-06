#test
{
    let values = [[10], [20, 30]]

    @assert(values[1][0] == 20)
    @assert(values[1, 0] == 20)
    @assert(values[1, 1] == 30)
}
