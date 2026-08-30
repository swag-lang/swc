#global private

#test
{
    var x: [2, 2] s32 = [[1, 2], [3, 4]]
    Swag.assert(x[0, 0] == 1)
    Swag.assert(x[0, 1] == 2)
    Swag.assert(x[1, 0] == 3)
    Swag.assert(x[1, 1] == 4)
}

#test
{
    const x: [2, 2] s32 = [[5, 6], [7, 8]]
    Swag.assert(x[0, 0] == 5)
    Swag.assert(x[0, 1] == 6)
    Swag.assert(x[1, 0] == 7)
    Swag.assert(x[1, 1] == 8)
}
