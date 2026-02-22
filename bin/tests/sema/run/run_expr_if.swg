#global internal

#test
{
    func ifTrueNoElse()->s32
    {
        if true
        {
            return 11
        }

        return 22
    }

    const V = #run ifTrueNoElse()
    #assert(V == 11)
}

#test
{
    func ifFalseNoElse()->s32
    {
        if false
        {
            return 11
        }

        return 22
    }

    const V = #run ifFalseNoElse()
    #assert(V == 22)
}

#test
{
    func ifElseTrue()->s32
    {
        if true
        {
            return 31
        }
        else
        {
            return 32
        }
    }

    const V = #run ifElseTrue()
    #assert(V == 31)
}

#test
{
    func ifElseFalse()->s32
    {
        if false
        {
            return 41
        }
        else
        {
            return 42
        }
    }

    const V = #run ifElseFalse()
    #assert(V == 42)
}

#test
{
    func ifElseIfMiddle()->s32
    {
        if false
        {
            return 51
        }
        elif true
        {
            return 52
        }
        else
        {
            return 53
        }
    }

    const V = #run ifElseIfMiddle()
    #assert(V == 52)
}

#test
{
    func ifElseIfLast()->s32
    {
        if false
        {
            return 61
        }
        elif false
        {
            return 62
        }
        else
        {
            return 63
        }
    }

    const V = #run ifElseIfLast()
    #assert(V == 63)
}

#test
{
    func nestedIf()->s32
    {
        if true
        {
            if false
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

    const V = #run nestedIf()
    #assert(V == 72)
}
