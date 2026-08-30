#global private

func semaTest001()
{
    var x: [2, 2] s32 = [[1, 2], [3, 4]]
    Swag.assert(x[0, 0] == 1)
    Swag.assert(x[0, 1] == 2)
    Swag.assert(x[1, 0] == 3)
    Swag.assert(x[1, 1] == 4)
}
