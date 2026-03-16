#global fileprivate // swc-option suite-jit

#test
{
    func nestedIndexCounters()->s32
    {
        var arr: [2] s32 = [4, 5]
        var outer: s32   = 0
        var inner: s32   = 0

        for arr
        {
            outer += cast(s32) @index

            foreach value in arr
            {
                if @index == 0 do
                    continue
                inner += value + cast(s32) @index
            }
        }

        return outer * 100 + inner
    }

    const V = #run nestedIndexCounters()
    #assert(V == 112)
}

#test
{
    func indexWithBreakContinue()->s32
    {
        var arr: [5] s32 = [3, 6, 9, 12, 15]
        var acc: s32     = 0

        for arr
        {
            if @index == 0 do
                continue
            if @index == 4 do
                break
            acc += arr[@index] + cast(s32) @index
        }

        return acc
    }

    const V = #run indexWithBreakContinue()
    #assert(V == 33)
}

#test
{
    func indexOnInlineCount()->s32
    {
        var acc: s32 = 0
        for 6
        {
            acc += cast(s32) @index * 3
        }

        return acc
    }

    const V = #run indexOnInlineCount()
    #assert(V == 45)
}
