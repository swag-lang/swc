#global fileprivate // swc-option suite-jit

#test
{
    func whileSum(n: s32)->s32
    {
        var i: s32 = 0
        var acc: s32 = 0
        while i < n
        {
            acc += i
            i += 1
        }

        return acc
    }

    const V = #run whileSum(6)
    #assert(V == 15)
}

#test
{
    func whileContinue(n: s32)->s32
    {
        var i: s32 = 0
        var acc: s32 = 0

        while i < n
        {
            i += 1
            if (i & 1) != 0
            {
                continue
            }

            acc += i
        }

        return acc
    }

    const V = #run whileContinue(6)
    #assert(V == 12)
}

#test
{
    func whileBreak()->s32
    {
        var i: s32 = 0
        while true
        {
            if i == 4
            {
                break
            }

            i += 1
        }

        return i
    }

    const V = #run whileBreak()
    #assert(V == 4)
}

#test
{
    func whileNested()->s32
    {
        var outer: s32 = 0
        var total: s32 = 0

        while outer < 4
        {
            outer += 1
            var inner: s32 = 0

            while inner < 5
            {
                inner += 1
                if inner == 2
                {
                    continue
                }

                if inner == 4
                {
                    break
                }

                total += outer * inner
            }
        }

        return total
    }

    const V = #run whileNested()
    #assert(V == 40)
}

#test
{
    func infiniteForLoopControl()->s32
    {
        var i: s32 = 0
        for
        {
            i += 1
            if i < 3
            {
                continue
            }

            break
        }

        return i
    }

    const V = #run infiniteForLoopControl()
    #assert(V == 3)
}
