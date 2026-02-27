#global fileprivate

#test
{
    func foreachArrayValueIndex()->s32
    {
        var arr: [5] s32 = [1, 2, 3, 4, 5]
        var acc: s32 = 0

        foreach v, i in arr
        {
            acc += v + cast(s32) i
        }

        return acc
    }

    const V = #run foreachArrayValueIndex()
    #assert(V == 25)
}

#test
{
    func foreachWhereControl()->s32
    {
        var arr: [8] s32 = [1, 2, 3, 4, 5, 6, 7, 8]
        var acc: s32 = 0

        foreach v in arr where (v & 1) == 0
        {
            if v == 6
            {
                continue
            }
            if v == 8
            {
                break
            }
            acc += v
        }

        return acc
    }

    const V = #run foreachWhereControl()
    #assert(V == 6)
}

#test
{
    func foreachByAddressRead()->s32
    {
        var arr: [4] s32 = [1, 2, 3, 4]
        var sum: s32 = 0

        foreach &v, i in arr
        {
            sum += dref v + cast(s32) i
        }

        return sum
    }

    const V = #run foreachByAddressRead()
    #assert(V == 16)
}

#test
{
    func foreachNoAlias()->u64
    {
        var arr: [3] s32 = [11, 22, 33]
        var count: u64 = 0

        foreach arr
        {
            count += 1
        }

        return count
    }

    const V = #run foreachNoAlias()
    #assert(V == 3)
}

#test
{
    func foreachStringValueIndex()->u32
    {
        var text: string = "ABC"
        var acc: u32 = 0

        foreach v, i in text
        {
            acc += cast(u32) v + cast(u32) i
        }

        return acc
    }

    const V = #run foreachStringValueIndex()
    #assert(V == 201'u32)
}

#test
{
    func foreachSliceValueIndex()->s32
    {
        var arr: [4] s32 = [5, 6, 7, 8]
        var sl = cast([..] s32) arr
        var acc: s32 = 0

        foreach v, i in sl
        {
            acc += v + cast(s32) i
        }

        return acc
    }

    const V = #run foreachSliceValueIndex()
    #assert(V == 32)
}

#test
{
    func foreachSliceWeighted()->s32
    {
        var arr: [4] s32 = [5, 6, 7, 8]
        var sl = cast([..] s32) arr
        var acc: s32 = 0
        foreach v, i in sl
        {
            acc += v * cast(s32) (i + 1)
        }

        return acc
    }

    const V = #run foreachSliceWeighted()
    #assert(V == 70)
}
