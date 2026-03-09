#global fileprivate

#test
{
    func countedLoop()->s32
    {
        var acc: s32 = 0
        for 10 do
            acc += 6
        return acc
    }

    const V = #run countedLoop()
    #assert(V == 60)
}

#test
{
    func rangeLoopWithControl()->s32
    {
        var acc: s32 = 0
        for i in 0 to 10
        {
            if i == 2 do
                continue
            if i == 7 do
                break
            acc += cast(s32) i
        }

        return acc
    }

    const V = #run rangeLoopWithControl()
    #assert(V == 19)
}

#test
{
    func arrayCountLoop()->s32
    {
        var arr: [4] s32 = [2, 4, 6, 8]
        var acc: s32     = 0
        for arr
        {
            acc += arr[@index] * cast(s32) (@index + 1)
        }

        return acc
    }

    const V = #run arrayCountLoop()
    #assert(V == 60)
}

#test
{
    func reverseRangeLoop()->s32
    {
        var acc: s32 = 0
        for #reverse i in 1 to 4
        {
            acc = acc * 10 + cast(s32) i
        }

        return acc
    }

    const V = #run reverseRangeLoop()
    #assert(V == 4321)
}
