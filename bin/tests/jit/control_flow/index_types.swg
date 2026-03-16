#global fileprivate // swc-option suite-jit

#test
{
    func countedIndexType()->u8
    {
        var last: u8 = 0
        for 4'u8
        {
            @assert(#typeof(@index) == u8)
            last = @index
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
            @assert(#typeof(@index) == s16)
            @assert(@index == i)
            acc += @index
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

        foreach value in arr
        {
            @assert(#typeof(@index) == u64)
            acc += @index + cast(u64) value
        }

        return acc
    }

    const V = #run foreachIndexType()
    #assert(V == 21'u64)
}
