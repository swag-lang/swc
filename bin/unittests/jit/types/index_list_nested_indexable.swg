#test
{
    let values = ["ab", "cde"]

    #assert(#typeof(values[0, 1]) == u8)
    Swag.require(values[0, 1] == values[0][1])
    Swag.require(values[1, 2] == values[1][2])
}
