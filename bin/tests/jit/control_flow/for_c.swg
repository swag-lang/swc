#global fileprivate // swc-option suite-jit

#test
{
    func sumLoop()->s32
    {
        var acc: s32 = 0
        for var i = 0; i < 8; i += 1
        {
            if i == 2 do
                continue
            if i == 6 do
                break
            acc += i
        }

        return acc
    }

    const V = #run sumLoop()
    #assert(V == 13)
}

#test
{
    func manualAdvance(limit: s32)->s32
    {
        var acc: s32 = 0
        for var i = 0; i < limit; ;
        {
            if i == 2
            {
                i += 1
                continue
            }

            acc += i
            i += 1
        }

        return acc
    }

    const V = #run manualAdvance(5)
    #assert(V == 8)
}
