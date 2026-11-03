#test
{
    let values = [[10], [20, 30]]

    Swag.require(values[1][0] == 20)
    Swag.require(values[1, 0] == 20)
    Swag.require(values[1, 1] == 30)
}

#test
{
    let values = [[1, 2], [5_000_000_000, 7]]

    #assert(#typeof(values) == [2][2] s64)
    #assert(#typeof(values[1]) == [2] s64)
    Swag.require(values[0, 1] == 2)
    Swag.require(values[1, 0] == 5_000_000_000)
}
