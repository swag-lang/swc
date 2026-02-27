#global fileprivate

#test
{
    func memsetAll()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        @memset(&data[0], 170'u8, 6)
        return data[0] == 170'u8 and
               data[1] == 170'u8 and
               data[2] == 170'u8 and
               data[3] == 170'u8 and
               data[4] == 170'u8 and
               data[5] == 170'u8
    }

    const V = #run memsetAll()
    #assert(V)
}

#test
{
    func memsetPartial()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        @memset(&data[2], 9'u8, 3)
        return data[0] == 1'u8 and
               data[1] == 2'u8 and
               data[2] == 9'u8 and
               data[3] == 9'u8 and
               data[4] == 9'u8 and
               data[5] == 6'u8
    }

    const V = #run memsetPartial()
    #assert(V)
}

#test
{
    func memsetZeroSize()->bool
    {
        var data: [4] u8 = [10, 11, 12, 13]
        @memset(&data[0], 0'u8, 0)
        return data[0] == 10'u8 and data[1] == 11'u8 and data[2] == 12'u8 and data[3] == 13'u8
    }

    const V = #run memsetZeroSize()
    #assert(V)
}
