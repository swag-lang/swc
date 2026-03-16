#global fileprivate // swc-option suite-jit

#test
{
    func untilLoopWithFilter()->s32
    {
        var acc: s32 = 0
        for i in 0 until 7 where i % 2 == 1
        {
            acc = acc * 10 + cast(s32) i
        }

        return acc
    }

    const V = #run untilLoopWithFilter()
    #assert(V == 135)
}

#test
{
    func reverseSignedRange()->s32
    {
        var acc: s32 = 0
        for #reverse i in -2 to 2
        {
            acc = acc * 10 + cast(s32) (i + 3)
        }

        return acc
    }

    const V = #run reverseSignedRange()
    #assert(V == 54321)
}

#test
{
    func filteredArrayLoop()->s32
    {
        var arr: [5] s32 = [2, 4, 6, 8, 10]
        var acc: s32     = 0
        for i in arr where arr[i] >= 6
        {
            acc += arr[i]
        }

        return acc
    }

    const V = #run filteredArrayLoop()
    #assert(V == 24)
}
