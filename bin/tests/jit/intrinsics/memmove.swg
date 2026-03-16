#global fileprivate // swc-option suite-jit

#test
{
    func memmoveOverlapRight()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        @memmove(&data[1], &data[0], 5)
        return data[0] == 1'u8 and
               data[1] == 1'u8 and
               data[2] == 2'u8 and
               data[3] == 3'u8 and
               data[4] == 4'u8 and
               data[5] == 5'u8
    }

    const V = #run memmoveOverlapRight()
    #assert(V)
}

#test
{
    func memmoveOverlapLeft()->bool
    {
        var data: [6] u8 = [1, 2, 3, 4, 5, 6]
        @memmove(&data[0], &data[1], 5)
        return data[0] == 2'u8 and
               data[1] == 3'u8 and
               data[2] == 4'u8 and
               data[3] == 5'u8 and
               data[4] == 6'u8 and
               data[5] == 6'u8
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
        @memmove(&dst[0], &src[0], 0)
        return dst[0] == 1'u8 and dst[1] == 2'u8 and dst[2] == 3'u8 and dst[3] == 4'u8
    }

    const V = #run memmoveZeroSize()
    #assert(V)
}
