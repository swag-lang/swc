#global private

#test
{
    func memsetAll()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        Swag.memset(&data[0], 170_u8, 6)
        return data[0] == 170_u8 and
               data[1] == 170_u8 and
               data[2] == 170_u8 and
               data[3] == 170_u8 and
               data[4] == 170_u8 and
               data[5] == 170_u8
    }

    const V = #run memsetAll()
    #assert(V)
}

#test
{
    func memsetPartial()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        Swag.memset(&data[2], 9_u8, 3)
        return data[0] == 1_u8 and
               data[1] == 2_u8 and
               data[2] == 9_u8 and
               data[3] == 9_u8 and
               data[4] == 9_u8 and
               data[5] == 6_u8
    }

    const V = #run memsetPartial()
    #assert(V)
}

#test
{
    func memsetZeroSize()->bool
    {
        var data: [4] u8 = [10, 11, 12, 13]
        Swag.memset(&data[0], 0_u8, 0)
        return data[0] == 10_u8 and data[1] == 11_u8 and data[2] == 12_u8 and data[3] == 13_u8
    }

    const V = #run memsetZeroSize()
    #assert(V)
}
