#global fileprivate // swc-option suite-jit

#test
{
    func memcpyAll()->bool
    {
        var src: [6] u8 = [1, 2, 3, 4, 5, 6]
        var dst: [6] u8 = [0, 0, 0, 0, 0, 0]
        @memcpy(&dst[0], &src[0], 6)
        return @memcmp(&dst[0], &src[0], 6) == 0
    }

    const V = #run memcpyAll()
    #assert(V)
}

#test
{
    func memcpyPartial()->bool
    {
        var src: [6] u8 = [10, 11, 12, 13, 14, 15]
        var dst: [6] u8 = [1, 2, 3, 4, 5, 6]
        @memcpy(&dst[2], &src[1], 3)
        return dst[0] == 1'u8 and
               dst[1] == 2'u8 and
               dst[2] == 11'u8 and
               dst[3] == 12'u8 and
               dst[4] == 13'u8 and
               dst[5] == 6'u8
    }

    const V = #run memcpyPartial()
    #assert(V)
}

#test
{
    func memcpyZeroSize()->bool
    {
        var src: [3] u8 = [7, 8, 9]
        var dst: [3] u8 = [1, 2, 3]
        @memcpy(&dst[0], &src[0], 0)
        return dst[0] == 1'u8 and dst[1] == 2'u8 and dst[2] == 3'u8
    }

    const V = #run memcpyZeroSize()
    #assert(V)
}
