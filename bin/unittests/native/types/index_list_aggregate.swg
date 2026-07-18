#global #[Swag.ExplicitNullability]
#test
{
    let values = [[10], [20, 30]]

    @assert(values[1][0] == 20)
    @assert(values[1, 0] == 20)
    @assert(values[1, 1] == 30)
}

#test
{
    let values = [[1, 2], [5_000_000_000, 7]]

    #assert(#typeof(values) == [2][2] s64)
    #assert(#typeof(values[1]) == [2] s64)
    @assert(values[0, 1] == 2)
    @assert(values[1, 0] == 5_000_000_000)
}
