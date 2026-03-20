#global fileprivate

func nativeIfLetSimple()->s32
{
    if let x = 1
    {
        return x
    }
    else
    {
        return x + 10
    }
}

func nativeIfLetWhereFalseElse()->s32
{
    if let x = 1 where false
    {
        return -1
    }
    else
    {
        return x + 2
    }
}

func nativeIfLetDo()->s32
{
    if let x = 4 where x > 2 do
        return x + 1

    return -1
}

#test
{
    @assert(nativeIfLetSimple() == 1)
}

#test
{
    @assert(nativeIfLetWhereFalseElse() == 3)
}

#test
{
    @assert(nativeIfLetDo() == 5)
}
