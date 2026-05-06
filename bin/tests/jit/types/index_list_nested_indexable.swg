#test
{
    let values = ["ab", "cde"]

    #assert(#typeof(values[0, 1]) == u8)
    @assert(values[0, 1] == values[0][1])
    @assert(values[1, 2] == values[1][2])
}
