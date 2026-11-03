#global private

#test
{
    var x: [2, 2] s32 = [[1, 2], [3, 4]]
    Swag.require(x[0, 0] == 1)
    Swag.require(x[0, 1] == 2)
    Swag.require(x[1, 0] == 3)
    Swag.require(x[1, 1] == 4)
}

#test
{
    const x: [2, 2] s32 = [[5, 6], [7, 8]]
    Swag.require(x[0, 0] == 5)
    Swag.require(x[0, 1] == 6)
    Swag.require(x[1, 0] == 7)
    Swag.require(x[1, 1] == 8)
}
