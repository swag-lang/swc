#global internal

#test
{
    #[Swag.PrintMicro]
    func ifArgNoElse()->s32
    {
        if false
        {
            return 12
        }

        return 11
    }

    const V0 = #run ifArgNoElse()
    #assert(V0 == 11)
}


#test
{
    func ifArgNoElse(flag: bool)->s32
    {
        if flag
        {
            return 11
        }

        return 22
    }

    const V0 = #run ifArgNoElse(true)
    const V1 = #run ifArgNoElse(false)
    #assert(V0 == 11)
    #assert(V1 == 22)
}

#test
{
    func ifElseArg(flag: bool)->s32
    {
        if flag
        {
            return 31
        }
        else
        {
            return 32
        }
    }

    const V0 = #run ifElseArg(true)
    const V1 = #run ifElseArg(false)
    #assert(V0 == 31)
    #assert(V1 == 32)
}

#test
{
    func ifElseIfArgs(flag0: bool, flag1: bool)->s32
    {
        if flag0
        {
            return 51
        }
        elif flag1
        {
            return 52
        }
        else
        {
            return 53
        }
    }

    const V0 = #run ifElseIfArgs(true, false)
    const V1 = #run ifElseIfArgs(false, true)
    const V2 = #run ifElseIfArgs(false, false)
    #assert(V0 == 51)
    #assert(V1 == 52)
    #assert(V2 == 53)
}

#test
{
    func nestedIfArgs(outer: bool, inner: bool)->s32
    {
        if outer
        {
            if inner
            {
                return 71
            }
            else
            {
                return 72
            }
        }

        return 73
    }

    const V0 = #run nestedIfArgs(true, true)
    const V1 = #run nestedIfArgs(true, false)
    const V2 = #run nestedIfArgs(false, true)
    #assert(V0 == 71)
    #assert(V1 == 72)
    #assert(V2 == 73)
}
