#global private

#test
{
    func memmoveOverlapRight()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        Swag.memmove(&data[1], &data[0], 5)
        return data[0] == 1_u8 and
               data[1] == 1_u8 and
               data[2] == 2_u8 and
               data[3] == 3_u8 and
               data[4] == 4_u8 and
               data[5] == 5_u8
    }

    const V = #run memmoveOverlapRight()
    #assert(V)
}

#test
{
    func memmoveOverlapLeft()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        Swag.memmove(&data[0], &data[1], 5)
        return data[0] == 2_u8 and
               data[1] == 3_u8 and
               data[2] == 4_u8 and
               data[3] == 5_u8 and
               data[4] == 6_u8 and
               data[5] == 6_u8
    }

    const V = #run memmoveOverlapLeft()
    #assert(V)
}

#test
{
    func memmoveZeroSize()->bool
    {
        var src: [4] u8 = [9, 8, 7, 6]
        var dst: [4] u8 = [1, 2, 3, 4]
        Swag.memmove(&dst[0], &src[0], 0)
        return dst[0] == 1_u8 and dst[1] == 2_u8 and dst[2] == 3_u8 and dst[3] == 4_u8
    }

    const V = #run memmoveZeroSize()
    #assert(V)
}
