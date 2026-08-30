#global private

#test
{
    func countedIndexType()->u8
    {
        var last: u8 = 0
        for 4'u8
        {
            Swag.assert(#typeof(Swag.index) == u8)
            last = Swag.index
        }

        return last
    }

    const V = #run countedIndexType()
    #assert(V == 3'u8)
}

#test
{
    func rangeIndexType()->s16
    {
        var acc: s16 = 0
        for i in 1's16 until 4's16
        {
            Swag.assert(#typeof(Swag.index) == s16)
            Swag.assert(Swag.index == i)
            acc += Swag.index
        }

        return acc
    }

    const V = #run rangeIndexType()
    #assert(V == 6's16)
}

#test
{
    func foreachIndexType()->u64
    {
        var arr: [3] u8 = [5, 6, 7]
        var acc: u64    = 0

        for value in arr
        {
            Swag.assert(#typeof(Swag.index) == u64)
            acc += Swag.index + cast(u64) value
        }

        return acc
    }

    const V = #run foreachIndexType()
    #assert(V == 21'u64)
}

#test
{
    func countLikeIndexType()->u64
    {
        var arr: [3] u8 = [5, 6, 7]
        var str: string = "abcd"
        var acc: u64    = 0

        for i in arr.count
        {
            acc += cast(u64) i
        }

        for i in str.count
        {
            Swag.assert(#typeof(i) == u64)
            Swag.assert(#typeof(Swag.index) == u64)
            acc += i
        }

        return acc
    }

    const V = #run countLikeIndexType()
    #assert(V == 9'u64)
}
